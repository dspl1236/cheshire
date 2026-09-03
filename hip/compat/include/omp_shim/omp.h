// Cheshire toolchain shim: clang-cl with -fopenmp defines _OPENMP=201811 but the only
// omp.h on this box is MSVC's OpenMP 2.0 header, which lacks the 3.0+ declarations
// AliceVision/vlfeat call (omp_get_thread_limit ...). MSVC's libomp.lib is LLVM's
// runtime and exports them, so only the declarations are missing.
#pragma once
#include_next <omp.h>

#ifdef __cplusplus
extern "C" {
#endif
/* OpenMP 3.0 */
int    omp_get_thread_limit(void);
void   omp_set_max_active_levels(int);
int    omp_get_max_active_levels(void);
int    omp_get_level(void);
int    omp_get_ancestor_thread_num(int);
int    omp_get_team_size(int);
int    omp_get_active_level(void);
void   omp_set_schedule(int, int);
void   omp_get_schedule(int*, int*);
/* OpenMP 3.1 / 4.0 */
int    omp_in_final(void);
int    omp_get_cancellation(void);
int    omp_get_proc_bind(void);
int    omp_get_num_devices(void);
int    omp_get_default_device(void);
void   omp_set_default_device(int);
int    omp_is_initial_device(void);
/* OpenMP 4.5 / 5.0 */
int    omp_get_max_task_priority(void);
int    omp_get_num_places(void);
int    omp_get_place_num_procs(int);
int    omp_get_place_num(void);
int    omp_get_partition_num_places(void);
#ifdef __cplusplus
}
#endif
