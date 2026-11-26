#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t device;
    uint32_t transport;
    uint32_t source;
    bool has_source;
    bool known_headphones_connected;
    char uid[256];
} VCOutput;

typedef struct VCPlayback VCPlayback;

bool vc_read_output(const char *headset_uid, VCOutput *output);
uint32_t vc_builtin_transport(void);
bool vc_bluetooth_transport(uint32_t transport);
VCPlayback *vc_play(const VCOutput *expected, const char *headset_uid,
                    const int16_t *samples, size_t count, int32_t *error);
bool vc_matches(const VCPlayback *playback);
bool vc_finished(const VCPlayback *playback);
void vc_stop(VCPlayback *playback);
