// Copyright 2012 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//  FUCKIN OBJECTIVE-C++ IS A FUCKING SHIT BROCHACHO

#include "base/time/time.h"

#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>

#include "base/apple/mach_logging.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/apple/scoped_mach_port.h"
#include "base/logging.h"
#include "base/numerics/safe_conversions.h"
#include "base/time/time_override.h"
#include "build/build_config.h"

namespace {

inline mach_timebase_info_data_t* MachTimebaseInfo() {
  static mach_timebase_info_data_t timebase_info = [] {
    mach_timebase_info_data_t info;
    kern_return_t kr = mach_timebase_info(&info);
    if (__builtin_expect(kr != KERN_SUCCESS, 0)) {
      MACH_DLOG(ERROR, kr) << "mach_timebase_info";
    }
    return info;
  }();
  return &timebase_info;
}

int64_t MachTimeToMicroseconds(uint64_t mach_time) {
  const mach_timebase_info_data_t* const timebase_info = MachTimebaseInfo();

  if (__builtin_expect(timebase_info->numer == timebase_info->denom, 1)) {
    return static_cast<int64_t>(mach_time / base::Time::kNanosecondsPerMicrosecond);
  }

  const uint64_t divisor = static_cast<uint64_t>(timebase_info->denom) * base::Time::kNanosecondsPerMicrosecond;
  uint64_t microseconds = mach_time / divisor;
  const uint64_t remainder = mach_time % divisor;

  CHECK(!__builtin_umulll_overflow(microseconds, timebase_info->numer, &microseconds));

  uint64_t extra_micros = (remainder * timebase_info->numer) / divisor;
  CHECK(!__builtin_uaddll_overflow(microseconds, extra_micros, &microseconds));

  return base::checked_cast<int64_t>(microseconds);
}

inline int64_t ComputeCurrentTicks() {
  return MachTimeToMicroseconds(mach_absolute_time());
}

int64_t ComputeThreadTicks() {
  struct timespec ts;
  if (__builtin_expect(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0, 0)) {
    return 0;
  }
  return (static_cast<int64_t>(ts.tv_sec) * base::Time::kMicrosecondsPerSecond) +
         (ts.tv_nsec / base::Time::kNanosecondsPerMicrosecond);
}

}

namespace base {

namespace subtle {
Time TimeNowIgnoringOverride() {
  return Time::FromCFAbsoluteTime(CFAbsoluteTimeGetCurrent());
}

Time TimeNowFromSystemTimeIgnoringOverride() {
  return TimeNowIgnoringOverride();
}
}

Time Time::FromCFAbsoluteTime(CFAbsoluteTime t) {
  if (t == 0) return Time();
  if (__builtin_expect(t == std::numeric_limits<CFAbsoluteTime>::infinity(), 0)) return Max();
  
  return UnixEpoch() + Seconds(t + kCFAbsoluteTimeIntervalSince1970);
}

CFAbsoluteTime Time::ToCFAbsoluteTime() const {
  if (is_null()) return 0;
  if (is_max()) return std::numeric_limits<CFAbsoluteTime>::infinity();
  
  return ((*this - UnixEpoch()).InSecondsF() - kCFAbsoluteTimeIntervalSince1970);
}

Time Time::FromNSDate(NSDate* date) {
  return FromCFAbsoluteTime([date timeIntervalSinceReferenceDate]);
}

NSDate* Time::ToNSDate() const {
  return [NSDate dateWithTimeIntervalSinceReferenceDate:ToCFAbsoluteTime()];
}

TimeDelta TimeDelta::FromMachTime(uint64_t mach_time) {
  return Microseconds(MachTimeToMicroseconds(mach_time));
}

namespace subtle {
TimeTicks TimeTicksNowIgnoringOverride() {
  return TimeTicks() + Microseconds(ComputeCurrentTicks());
}

TimeTicks TimeTicksLowResolutionNowIgnoringOverride() {
  return TimeTicks() + Microseconds(MachTimeToMicroseconds(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW_APPROX)));
}
}

bool TimeTicks::IsHighResolution() {
  return true;
}

bool TimeTicks::IsConsistentAcrossProcesses() {
  return true;
}

TimeTicks TimeTicks::FromMachAbsoluteTime(uint64_t mach_absolute_time) {
  return TimeTicks(MachTimeToMicroseconds(mach_absolute_time));
}

mach_timebase_info_data_t TimeTicks::SetMachTimebaseInfoForTesting(mach_timebase_info_data_t timebase) {
  mach_timebase_info_data_t* info = MachTimebaseInfo();
  mach_timebase_info_data_t orig = *info;
  *info = timebase;
  return orig;
}

TimeTicks::Clock TimeTicks::GetClock() {
  return Clock::MAC_MACH_ABSOLUTE_TIME;
}

namespace subtle {
ThreadTicks ThreadTicksNowIgnoringOverride() {
  return ThreadTicks() + Microseconds(ComputeThreadTicks());
}
}

}
