// Copyright 2026 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>

// OpenHarmony's libc keeps pthread-specific values in an indirect TSD
// vector. The arm64 runtime reads that vector directly because a shared
// library loaded after process startup cannot use initial-exec ELF TLS.
static void
inittls(void **tlsg, void **tlsbase)
{
	pthread_key_t key;
	int err = pthread_key_create(&key, 0);
	if (err != 0) {
		abort();
	}
	*tlsg = (void *)((uintptr_t)key * sizeof(void *));
}

void (*x_cgo_inittls)(void **tlsg, void **tlsbase) = inittls;
