#include <stdio.h>
#include <stdlib.h>
#include <thread>
#include <algorithm>
#include "CycleTimer.h"

static constexpr int MAX_THREADS = 32;

struct alignas(64) PaddedDouble
{
    double value = 0.0;
};

static PaddedDouble g_thread_times[MAX_THREADS];

typedef struct {
    float x0, x1;
    float y0, y1;
    unsigned int width;
    unsigned int height;
    int maxIterations;
    int* output;
    int threadId;
    int numThreads;
} WorkerArgs;


extern void mandelbrotSerial(
    float x0, float y0, float x1, float y1,
    int width, int height,
    int startRow, int numRows,
    int maxIterations,
    int output[]);


void workerThreadStart(WorkerArgs * const args)
{
    const int threadId = args->threadId;
    const int numThreads = args->numThreads;
    const int width = static_cast<int>(args->width);
    const int height = static_cast<int>(args->height);

    const double startTime = CycleTimer::currentSeconds();

    for (int row = threadId; row < height; row += numThreads)
    {
        mandelbrotSerial(
            args->x0, args->y0,
            args->x1, args->y1,
            width, height,
            row, 1,
            args->maxIterations,
            args->output
        );
    }

    const double endTime = CycleTimer::currentSeconds();

    g_thread_times[threadId].value = endTime - startTime;
}

void mandelbrotThread(
    int numThreads,
    float x0, float y0, float x1, float y1,
    int width, int height,
    int maxIterations, int output[])
{
    if (numThreads > MAX_THREADS)
    {
        fprintf(stderr, "Error: Max allowed threads is %d\n", MAX_THREADS);
        exit(1);
    }

    for (int i = 0; i < MAX_THREADS; ++i)
    {
        g_thread_times[i].value = 0.0;
    }

    std::thread workers[MAX_THREADS];
    WorkerArgs args[MAX_THREADS];

    for (int i = 0; i < numThreads; i++)
    {
        args[i].x0 = x0;
        args[i].y0 = y0;
        args[i].x1 = x1;
        args[i].y1 = y1;
        args[i].width = width;
        args[i].height = height;
        args[i].maxIterations = maxIterations;
        args[i].numThreads = numThreads;
        args[i].output = output;

        args[i].threadId = i;
    }

    for (int i = 1; i < numThreads; i++)
    {
        workers[i] = std::thread(workerThreadStart, &args[i]);
    }

    workerThreadStart(&args[0]);

    for (int i = 1; i < numThreads; i++)
    {
        workers[i].join();
    }

    if (getenv("PRINT_THREAD_TIMES") != nullptr)
    {
        double maxTime = 0.0;
        double minTime = 1e30;
        double sumTime = 0.0;

        printf("\n--- thread times ---\n");

        for (int i = 0; i < numThreads; ++i)
        {
            const double t = g_thread_times[i].value;

            printf("thread %2d: %.3f ms\n", i, t * 1000.0);

            maxTime = std::max(maxTime, t);
            minTime = std::min(minTime, t);
            sumTime += t;
        }

        const double avgTime = sumTime / static_cast<double>(numThreads);
        const double imbalance = (minTime > 0.0) ? (maxTime / minTime) : 0.0;

        printf("max thread time: %.3f ms\n", maxTime * 1000.0);
        printf("min thread time: %.3f ms\n", minTime * 1000.0);
        printf("avg thread time: %.3f ms\n", avgTime * 1000.0);
        printf("max/min imbalance: %.3f\n", imbalance);
        printf("--------------------\n\n");
    }
}