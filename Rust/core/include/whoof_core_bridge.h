#ifndef WHOOF_CORE_BRIDGE_H
#define WHOOF_CORE_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

char *whoof_core_version_json(void);
char *whoof_bridge_handle_json(const char *request_json);
void whoof_bridge_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
