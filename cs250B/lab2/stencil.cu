#include <time.h>
#include <stdio.h>
#include <iostream>
#include <math.h>

#include <ctime>
#include <chrono>

__device__
inline int idx(int x, int y, int width) {
	return y*width+x;
}

__global__ void stencil_kernel(float* temp, float* temp2, float* conduct, int w, int h) {
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int x = i % w, y = i / w;
	if (x > 0 && y > 0 && x < (w-1) && y < (h-1)) {
		float e = temp[i];
		temp2[i] = e +
			(
				(temp[i-1] - e) * conduct[i-1]
				+
				(temp[i+1] - e) * conduct[i+1]
				+
				(temp[i-w] - e) * conduct[i-w]
				+
				(temp[i+w] - e) * conduct[i+w]
			) * 0.2;
	}
}

void stencil_parallel(float* temp, float* temp2, float* conduct, int width, int height, int steps) {
	int n = width * height;
	// int threads = 1024;
	// int threads = 512;
	// int threads = 256;
	int threads = 128;
	// int threads = 64;
	int blocks = (n + threads - 1) / threads;

	for ( int s = 0; s < steps; s++ ) {
		stencil_kernel<<<blocks,threads>>>(temp, temp2, conduct, width, height);
		float* t = temp;
		temp = temp2;
		temp2 = t;
	}
}

__global__
void stencil_cuda(float* temp, float* temp2, float* conduct, int width, int height, int steps) {
	for ( int s = 0; s < steps; s++ ) {
		for ( int i = 1; i < width-1; i++ ) {
			for ( int j = 1; j < height-1; j++ ) {
				temp2[idx(i,j,width)] = 
					temp[idx(i,j,width)] +
					(
						(temp[idx(i-1,j,width)] - temp[idx(i,j,width)]) * conduct[idx(i-1,j,width)]
						+ 
						(temp[idx(i+1,j,width)] - temp[idx(i,j,width)]) * conduct[idx(i+1,j,width)]
						+ 
						(temp[idx(i,j-1,width)] - temp[idx(i,j,width)]) * conduct[idx(i,j-1,width)]
						+ 
						(temp[idx(i,j+1,width)] - temp[idx(i,j,width)]) * conduct[idx(i,j+1,width)]
					) * 0.2;
			}
		}
		float* t = temp;
		temp = temp2;
		temp2 = t;
	}
}

void stencil_optimized(float* temp, float* conduct, int width, int height, int steps) {
	int deviceCount;
	cudaGetDeviceCount(&deviceCount);
	printf( "Number of CUDA devices: %d\n", deviceCount );
	for ( int i = 0; i < deviceCount; i++ ) {
		cudaDeviceProp prop;
		cudaGetDeviceProperties(&prop, i);
		printf( "%d: %s\n", i, prop.name );
		printf( "Max %d threads per block\n", prop.maxThreadsPerBlock );
	}


	printf( "Starting cuda for %d steps on %dx%dx\n", steps, width, height );
	//cudaMemcpy(da, ha, N*sizeof(float), cudaMemcpyHostToDevice);
	float* dtemp, *dtemp2, *dconduct;
	cudaMalloc(&dtemp, width*height*sizeof(float));
	cudaMalloc(&dtemp2, width*height*sizeof(float));
	cudaMalloc(&dconduct, width*height*sizeof(float));

	cudaMemcpy(dtemp, temp, width*height*sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dconduct, conduct, width*height*sizeof(float), cudaMemcpyHostToDevice);

	// stencil_cuda<<<1,1>>>(dtemp,dtemp2,dconduct,width,height,steps);
	stencil_parallel(dtemp,dtemp2,dconduct,width,height,steps);
	printf( "Started kernel\n" );
	cudaDeviceSynchronize();
	
	if ( steps % 2 == 0 ) {
		cudaMemcpy(temp, dtemp, width*height*sizeof(float), cudaMemcpyDeviceToHost);
	} else {
		cudaMemcpy(temp, dtemp2, width*height*sizeof(float), cudaMemcpyDeviceToHost);
	}
}
