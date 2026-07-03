#import "GeneratedPluginRegistrant.h"

// Declare torrent native functions to expose to Swift and prevent linker stripping
extern char* anivault_torrent_init(char* downloadDir);
extern char* anivault_torrent_add_magnet(char* magnet);
extern char* anivault_torrent_pause(char* id);
extern char* anivault_torrent_resume(char* id);
extern char* anivault_torrent_remove(char* id, int dropData);
extern char* anivault_torrent_status(void);
extern void anivault_torrent_free(char* ptr);
