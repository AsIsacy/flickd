#ifndef MULTITOUCH_SUPPORT_H
#define MULTITOUCH_SUPPORT_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef enum {
    MTTouchStateNotTracking  = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch    = 3,
    MTTouchStateTouching     = 4,
    MTTouchStateBreakTouch   = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange   = 7
} MTTouchState;

typedef struct {
    int32_t  frame;
    double   timestamp;
    int32_t  pathIndex;
    int32_t  state;
    int32_t  fingerID;
    int32_t  handID;
    MTVector normalizedVector;
    float    zTotal;
    int32_t  field9;
    float    angle;
    float    majorAxis;
    float    minorAxis;
    MTVector absoluteVector;
    int32_t  field14;
    int32_t  field15;
    float    zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches, int numTouches, double timestamp, int frame);

#endif /* MULTITOUCH_SUPPORT_H */
