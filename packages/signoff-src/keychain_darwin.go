//go:build darwin && cgo

package main

/*
#cgo CFLAGS: -Wno-deprecated-declarations
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <Security/Security.h>

static char *signoff_cfstring(CFStringRef s) {
	if (s == NULL) return strdup("unknown error");
	CFIndex size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), kCFStringEncodingUTF8) + 1;
	char *out = malloc(size);
	if (!CFStringGetCString(s, out, size, kCFStringEncodingUTF8)) strcpy(out, "unprintable error");
	return out;
}

static char *signoff_status(OSStatus status) {
	CFStringRef message = SecCopyErrorMessageString(status, NULL);
	char *out = signoff_cfstring(message);
	if (message) CFRelease(message);
	return out;
}

// signoff_private_keys returns the RSA private key refs in one keychain file.
// Only refs are returned: no key data, and no use of any key.
static CFArrayRef signoff_private_keys(const char *path, char **err) {
	SecKeychainRef keychain = NULL;
	OSStatus status = SecKeychainOpen(path, &keychain);
	if (status != errSecSuccess) {
		*err = signoff_status(status);
		return NULL;
	}
	CFArrayRef searchList = CFArrayCreate(NULL, (const void **)&keychain, 1, &kCFTypeArrayCallBacks);
	CFRelease(keychain);
	const void *keys[] = {kSecClass, kSecAttrKeyClass, kSecAttrKeyType, kSecMatchSearchList, kSecReturnRef, kSecMatchLimit};
	const void *vals[] = {kSecClassKey, kSecAttrKeyClassPrivate, kSecAttrKeyTypeRSA, searchList, kCFBooleanTrue, kSecMatchLimitAll};
	CFDictionaryRef query = CFDictionaryCreate(NULL, keys, vals, 6, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFArrayRef items = NULL;
	status = SecItemCopyMatching(query, (CFTypeRef *)&items);
	CFRelease(query);
	CFRelease(searchList);
	if (status == errSecItemNotFound) return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
	if (status != errSecSuccess) {
		*err = signoff_status(status);
		return NULL;
	}
	return items;
}

// signoff_public_der returns the PKCS#1 public half of a private key, or NULL.
static CFDataRef signoff_public_der(SecKeyRef key) {
	SecKeyRef pub = SecKeyCopyPublicKey(key);
	if (pub == NULL) return NULL;
	CFDataRef der = SecKeyCopyExternalRepresentation(pub, NULL);
	CFRelease(pub);
	return der;
}

// signoff_public_keys lists the public halves of every RSA private key in path.
static int signoff_public_keys(const char *path, unsigned char ***ders, long **lens, long *count, char **err) {
	CFArrayRef items = signoff_private_keys(path, err);
	if (items == NULL) return 1;
	CFIndex n = CFArrayGetCount(items);
	*ders = calloc(n + 1, sizeof(unsigned char *));
	*lens = calloc(n + 1, sizeof(long));
	*count = 0;
	for (CFIndex i = 0; i < n; i++) {
		CFDataRef der = signoff_public_der((SecKeyRef)CFArrayGetValueAtIndex(items, i));
		if (der == NULL) continue;
		long len = CFDataGetLength(der);
		(*ders)[*count] = malloc(len);
		memcpy((*ders)[*count], CFDataGetBytePtr(der), len);
		(*lens)[*count] = len;
		(*count)++;
		CFRelease(der);
	}
	CFRelease(items);
	return 0;
}

// signoff_sign signs msg in place with the private key whose public half is
// exactly pub. The private key never leaves the Security framework.
static int signoff_sign(const char *path, const void *pub, long pubLen, const void *msg, long msgLen, void **sig, long *sigLen, char **err) {
	CFArrayRef items = signoff_private_keys(path, err);
	if (items == NULL) return 1;
	SecKeyRef key = NULL;
	CFIndex n = CFArrayGetCount(items);
	for (CFIndex i = 0; i < n && key == NULL; i++) {
		SecKeyRef candidate = (SecKeyRef)CFArrayGetValueAtIndex(items, i);
		CFDataRef der = signoff_public_der(candidate);
		if (der == NULL) continue;
		if (CFDataGetLength(der) == pubLen && memcmp(CFDataGetBytePtr(der), pub, pubLen) == 0) key = candidate;
		CFRelease(der);
	}
	if (key == NULL) {
		CFRelease(items);
		*err = strdup("the selected key is no longer in the keychain");
		return 1;
	}
	CFDataRef data = CFDataCreate(NULL, msg, msgLen);
	CFErrorRef cfErr = NULL;
	CFDataRef signature = SecKeyCreateSignature(key, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, data, &cfErr);
	CFRelease(data);
	CFRelease(items);
	if (signature == NULL) {
		CFStringRef message = cfErr ? CFErrorCopyDescription(cfErr) : NULL;
		*err = signoff_cfstring(message);
		if (message) CFRelease(message);
		if (cfErr) CFRelease(cfErr);
		return 1;
	}
	*sigLen = CFDataGetLength(signature);
	*sig = malloc(*sigLen);
	memcpy(*sig, CFDataGetBytePtr(signature), *sigLen);
	CFRelease(signature);
	return 0;
}
*/
import "C"

import (
	"errors"
	"fmt"
	"unsafe"
)

// keychainSigner signs with the RSA private key in keychainPath whose GitHub
// fingerprint is fp. Candidates are matched by public key only; no candidate
// is ever trial-signed, so only the selected key can raise a Keychain prompt.
func keychainSigner(keychainPath, fp string) func([]byte) ([]byte, error) {
	return func(msg []byte) ([]byte, error) {
		cPath := C.CString(keychainPath)
		defer C.free(unsafe.Pointer(cPath))
		keys, err := keychainPublicKeys(cPath)
		if err != nil {
			return nil, fmt.Errorf("keychain %s: %w", keychainPath, err)
		}
		pub, err := matchKey(keys, fp)
		if err != nil {
			return nil, fmt.Errorf("keychain %s: %w", keychainPath, err)
		}
		var sig unsafe.Pointer
		var sigLen C.long
		var cErr *C.char
		if C.signoff_sign(cPath, unsafe.Pointer(&pub[0]), C.long(len(pub)), unsafe.Pointer(&msg[0]), C.long(len(msg)), &sig, &sigLen, &cErr) != 0 {
			defer C.free(unsafe.Pointer(cErr))
			return nil, fmt.Errorf("keychain %s: %s", keychainPath, C.GoString(cErr))
		}
		defer C.free(sig)
		return C.GoBytes(sig, C.int(sigLen)), nil
	}
}

func keychainPublicKeys(path *C.char) ([][]byte, error) {
	var ders **C.uchar
	var lens *C.long
	var count C.long
	var cErr *C.char
	if C.signoff_public_keys(path, &ders, &lens, &count, &cErr) != 0 {
		defer C.free(unsafe.Pointer(cErr))
		return nil, errors.New(C.GoString(cErr))
	}
	defer C.free(unsafe.Pointer(ders))
	defer C.free(unsafe.Pointer(lens))
	derSlice, lenSlice := unsafe.Slice(ders, count), unsafe.Slice(lens, count)
	keys := make([][]byte, count)
	for i := range keys {
		keys[i] = C.GoBytes(unsafe.Pointer(derSlice[i]), C.int(lenSlice[i]))
		C.free(unsafe.Pointer(derSlice[i]))
	}
	return keys, nil
}
