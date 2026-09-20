//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<file_picker_darwin/FilePickerPlugin.h>)
#import <file_picker_darwin/FilePickerPlugin.h>
#else
@import file_picker_darwin;
#endif

#if __has_include(<offline_stt_darwin/OfflineSttDarwinPlugin.h>)
#import <offline_stt_darwin/OfflineSttDarwinPlugin.h>
#else
@import offline_stt_darwin;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FilePickerPlugin registerWithRegistrar:[registry registrarForPlugin:@"FilePickerPlugin"]];
  [OfflineSttDarwinPlugin registerWithRegistrar:[registry registrarForPlugin:@"OfflineSttDarwinPlugin"]];
}

@end
