#include "PinnedAudio.h"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct VCPlayback {
    AudioQueueRef queue;
    CFStringRef uid;
    atomic_bool finished;
};

static OSStatus read_property(AudioObjectID id, AudioObjectPropertySelector selector,
                              AudioObjectPropertyScope scope, UInt32 bytes, void *data) {
    AudioObjectPropertyAddress address = {selector, scope, kAudioObjectPropertyElementMain};
    return AudioObjectGetPropertyData(id, &address, 0, NULL, &bytes, data);
}

static CFStringRef read_uid(AudioDeviceID device) {
    CFStringRef uid = NULL;
    OSStatus status = read_property(device, kAudioDevicePropertyDeviceUID,
                                    kAudioObjectPropertyScopeGlobal, sizeof uid, &uid);
    return status == noErr ? uid : NULL;
}

static bool is_alive(AudioDeviceID device) {
    UInt32 alive = 0;
    return read_property(device, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal,
                         sizeof alive, &alive) == noErr && alive != 0;
}

static bool uid_is_present(const char *headset_uid) {
    if (!headset_uid || !headset_uid[0]) return false;
    CFStringRef wanted = CFStringCreateWithCString(NULL, headset_uid, kCFStringEncodingUTF8);
    if (!wanted) return true; // Uncertain presence must deny public speech.
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslateUIDToDevice,
                                          kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID found = kAudioObjectUnknown;
    UInt32 size = sizeof found;
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
                                                  sizeof wanted, &wanted, &size, &found);
    CFRelease(wanted);
    return status != noErr || (found != kAudioObjectUnknown && is_alive(found));
}

bool vc_read_output(const char *headset_uid, VCOutput *output) {
    memset(output, 0, sizeof *output);
    if (read_property(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice,
                      kAudioObjectPropertyScopeGlobal, sizeof output->device, &output->device) != noErr ||
        !is_alive(output->device)) return false;
    CFStringRef uid = read_uid(output->device);
    if (!uid) return false;
    bool has_uid = CFStringGetCString(uid, output->uid, sizeof output->uid, kCFStringEncodingUTF8);
    CFRelease(uid);
    if (!has_uid || !output->uid[0]) return false;
    if (read_property(output->device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal,
                      sizeof output->transport, &output->transport) != noErr) return false;
    output->has_source = read_property(output->device, kAudioDevicePropertyDataSource,
                                       kAudioDevicePropertyScopeOutput, sizeof output->source,
                                       &output->source) == noErr;
    output->known_headphones_connected = (headset_uid && strcmp(output->uid, headset_uid) == 0)
                                         || uid_is_present(headset_uid);
    return true;
}

uint32_t vc_builtin_transport(void) { return kAudioDeviceTransportTypeBuiltIn; }
bool vc_bluetooth_transport(uint32_t transport) {
    return transport == kAudioDeviceTransportTypeBluetooth ||
           transport == kAudioDeviceTransportTypeBluetoothLE;
}

static void finished_buffer(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)queue;
    (void)buffer;
    VCPlayback *playback = context;
    atomic_store(&playback->finished, true);
}

bool vc_matches(const VCPlayback *playback) {
    CFStringRef device = NULL;
    UInt32 size = sizeof device;
    OSStatus status = AudioQueueGetProperty(playback->queue, kAudioQueueProperty_CurrentDevice, &device, &size);
    bool matches = status == noErr && device && CFEqual(device, playback->uid);
    if (device) CFRelease(device);
    return matches;
}

bool vc_finished(const VCPlayback *playback) { return atomic_load(&playback->finished); }

void vc_stop(VCPlayback *playback) {
    if (!playback) return;
    if (playback->queue) {
        AudioQueueStop(playback->queue, true);
        if (AudioQueueDispose(playback->queue, true) != noErr) return;
    }
    if (playback->uid) CFRelease(playback->uid);
    free(playback);
}

VCPlayback *vc_play(const VCOutput *expected, const char *headset_uid,
                    const int16_t *samples, size_t count, int32_t *error) {
    *error = -1;
    if (count == 0 || count > 480000) return NULL;
    VCPlayback *playback = calloc(1, sizeof *playback);
    if (!playback) return NULL;
    atomic_init(&playback->finished, false);
    playback->uid = CFStringCreateWithCString(NULL, expected->uid, kCFStringEncodingUTF8);
    if (!playback->uid) {
        vc_stop(playback);
        return NULL;
    }
    AudioStreamBasicDescription format = {
        .mSampleRate = 16000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 2, .mFramesPerPacket = 1, .mBytesPerFrame = 2,
        .mChannelsPerFrame = 1, .mBitsPerChannel = 16
    };
    OSStatus status = AudioQueueNewOutput(&format, finished_buffer, playback, NULL, NULL, 0, &playback->queue);
    if (status == noErr)
        status = AudioQueueSetProperty(playback->queue, kAudioQueueProperty_CurrentDevice,
                                       &playback->uid, sizeof playback->uid);
    if (status == noErr && !vc_matches(playback)) status = -2;
    AudioQueueBufferRef buffer = NULL;
    const UInt32 bytes = (UInt32)(count * sizeof(int16_t));
    if (status == noErr) status = AudioQueueAllocateBuffer(playback->queue, bytes, &buffer);
    if (status == noErr) {
        memcpy(buffer->mAudioData, samples, bytes);
        buffer->mAudioDataByteSize = bytes;
        status = AudioQueueEnqueueBuffer(playback->queue, buffer, 0, NULL);
    }
    VCOutput current;
    if (status == noErr &&
        (!vc_read_output(headset_uid, &current) || current.device != expected->device ||
         strcmp(current.uid, expected->uid) != 0 || current.transport != expected->transport ||
         current.has_source != expected->has_source || current.source != expected->source ||
         current.known_headphones_connected != expected->known_headphones_connected)) status = -2;
    if (status == noErr) status = AudioQueueStart(playback->queue, NULL);
    *error = status;
    if (status == noErr) return playback;
    vc_stop(playback);
    return NULL;
}
