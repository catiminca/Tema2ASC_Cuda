#include <stdio.h>
#include <stdint.h>
#include "../include/utils.cuh"
#include <string.h>
#include <stdlib.h>
#include <inttypes.h>

// TODO: Implement function to search for all nonces from 1 through MAX_NONCE (inclusive) using CUDA Threads
__global__ void findNonce(int number_th, BYTE* block_content, size_t current_length, BYTE* block_hash, uint64_t* nonce_final, BYTE* difficulty_5_zeros, int* flag) {
	unsigned int th = threadIdx.x + blockDim.x * blockIdx.x;
	uint64_t start = th * (double)MAX_NONCE / number_th;
	uint64_t end = (th + 1) * MAX_NONCE / number_th;
	if (end > MAX_NONCE) {
		end = MAX_NONCE;
	}
	BYTE block_content_copy[BLOCK_SIZE], block_hash_copy[SHA256_HASH_SIZE];
	d_strcpy((char*) block_content_copy, (const char*) block_content);
	for (uint64_t nonce = start; nonce < end; nonce++) {
		char nonce_string[NONCE_SIZE];
		intToString(nonce, nonce_string);
		d_strcpy((char*) block_content_copy + current_length, nonce_string);
        apply_sha256(block_content_copy, d_strlen((const char*)block_content_copy), block_hash_copy, 1);
		if (compare_hashes(block_hash_copy, difficulty_5_zeros) <= 0) {
				atomicAdd(flag, 1);
				if (*flag == 1) {
					*nonce_final = nonce;
					d_strcpy((char*) block_hash, (const char*) block_hash_copy);
					d_strcpy((char*) block_content, (const char*) block_content_copy);
					break;
				}
			}
		if (*flag == 1) {
			break;
		}
	}
}

int main(int argc, char **argv) {
	BYTE hashed_tx1[SHA256_HASH_SIZE], hashed_tx2[SHA256_HASH_SIZE], hashed_tx3[SHA256_HASH_SIZE], hashed_tx4[SHA256_HASH_SIZE],
			tx12[SHA256_HASH_SIZE * 2], tx34[SHA256_HASH_SIZE * 2], hashed_tx12[SHA256_HASH_SIZE], hashed_tx34[SHA256_HASH_SIZE],
			tx1234[SHA256_HASH_SIZE * 2], top_hash[SHA256_HASH_SIZE], block_content[BLOCK_SIZE];
	BYTE block_hash[SHA256_HASH_SIZE] = "0000000000000000000000000000000000000000000000000000000000000000"; // TODO: Update
	uint64_t nonce = 0; // TODO: Update
	size_t current_length;

	// Top hash
	apply_sha256(tx1, strlen((const char*)tx1), hashed_tx1, 1);
	apply_sha256(tx2, strlen((const char*)tx2), hashed_tx2, 1);
	apply_sha256(tx3, strlen((const char*)tx3), hashed_tx3, 1);
	apply_sha256(tx4, strlen((const char*)tx4), hashed_tx4, 1);
	strcpy((char *)tx12, (const char *)hashed_tx1);
	strcat((char *)tx12, (const char *)hashed_tx2);
	apply_sha256(tx12, strlen((const char*)tx12), hashed_tx12, 1);
	strcpy((char *)tx34, (const char *)hashed_tx3);
	strcat((char *)tx34, (const char *)hashed_tx4);
	apply_sha256(tx34, strlen((const char*)tx34), hashed_tx34, 1);
	strcpy((char *)tx1234, (const char *)hashed_tx12);
	strcat((char *)tx1234, (const char *)hashed_tx34);
	apply_sha256(tx1234, strlen((const char*)tx34), top_hash, 1);

	// prev_block_hash + top_hash
	strcpy((char*)block_content, (const char*)prev_block_hash);
	strcat((char*)block_content, (const char*)top_hash);
	current_length = strlen((char*) block_content);

	cudaEvent_t start, stop;
	startTiming(&start, &stop);

	cudaDeviceProp props;
	cudaGetDeviceProperties(&props, 0);
	const size_t block_size = 256;
	size_t blocks_no = props.multiProcessorCount;

	//alocate memory for device arrays and copy the information
	int number_th = blocks_no * block_size;
	BYTE *block_hash_d, *block_content_d, *difficulty_5_zeros_d;
	uint64_t *nonce_d;
	cudaMalloc(&block_hash_d, SHA256_HASH_SIZE);
	if (block_hash_d == 0) {
		printf("[HOST]: Error allocating memory for block_hash_d\n");
		exit(1);
	}
	cudaMalloc(&block_content_d, BLOCK_SIZE);
	if (block_content_d == 0) {
		printf("[HOST]: Error allocating memory for block_content_d\n");
		exit(1);
	}
	cudaMemcpy(block_content_d, block_content, BLOCK_SIZE, cudaMemcpyHostToDevice);
	cudaMalloc(&nonce_d, sizeof(uint64_t));
	if (nonce_d == 0) {
		printf("[HOST]: Error allocating memory for nonce_d\n");
		exit(1);
	}
	cudaMalloc(&difficulty_5_zeros_d, SHA256_HASH_SIZE);
	if (difficulty_5_zeros_d == 0) {
		printf("[HOST]: Error allocating memory for difficulty_5_zeros_d\n");
		exit(1);
	}
	cudaMemcpy(difficulty_5_zeros_d, difficulty_5_zeros, SHA256_HASH_SIZE, cudaMemcpyHostToDevice);
	int *flag;
	cudaMalloc(&flag, sizeof(int));
	if (flag == 0) {
		printf("[HOST]: Error allocating memory for flag\n");
		exit(1);
	}
	cudaMemset(flag, 0, sizeof(int));
	findNonce<<<blocks_no, block_size>>>(number_th, block_content_d, current_length, block_hash_d, nonce_d, difficulty_5_zeros_d, flag);
	cudaDeviceSynchronize();
	//copy the results back to the host
	cudaMemcpy(block_hash, block_hash_d, SHA256_HASH_SIZE, cudaMemcpyDeviceToHost);
	cudaMemcpy(block_content, block_content_d, BLOCK_SIZE, cudaMemcpyDeviceToHost);
	cudaMemcpy(&nonce, nonce_d, sizeof(uint64_t), cudaMemcpyDeviceToHost);

	float seconds = stopTiming(&start, &stop);
	printResult(block_hash, nonce, seconds);

	// Free the memory for device
	cudaFree(block_hash_d);
	cudaFree(block_content_d);
	cudaFree(nonce_d);
	cudaFree(difficulty_5_zeros_d);
	cudaFree(flag);
	return 0;
}
