#ifndef DisplayBridge_h
#define DisplayBridge_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns 0 on success, non-zero on error
int setDisplayInput(int displayIndex, int inputValue);

// Display metadata
int getConnectedDisplayCount(void);
const char* getDisplayName(int displayIndex);

#ifdef __cplusplus
}
#endif

#endif /* DisplayBridge_h */
