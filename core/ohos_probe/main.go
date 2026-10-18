package main

/*
#include <stdint.h>
*/
import "C"

//export hna_probe
func hna_probe() C.int32_t {
	return 42
}

func main() {}
