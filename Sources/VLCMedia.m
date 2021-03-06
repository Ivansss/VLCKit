/*****************************************************************************
 * VLCMedia.m: VLCKit.framework VLCMedia implementation
 *****************************************************************************
 * Copyright (C) 2007 Pierre d'Herbemont
 * Copyright (C) 2013 Felix Paul K√ºhne
 * Copyright (C) 2007, 2013 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Felix Paul K√ºhne <fkuehne # videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCMedia.h"
#import "VLCMediaList.h"
#import "VLCEventManager.h"
#import "VLCLibrary.h"
#import "VLCLibVLCBridging.h"
#import <vlc/libvlc.h>
#import <sys/sysctl.h> // for sysctlbyname

/* Meta Dictionary Keys */
NSString *const VLCMetaInformationTitle          = @"title";
NSString *const VLCMetaInformationArtist         = @"artist";
NSString *const VLCMetaInformationGenre          = @"genre";
NSString *const VLCMetaInformationCopyright      = @"copyright";
NSString *const VLCMetaInformationAlbum          = @"album";
NSString *const VLCMetaInformationTrackNumber    = @"trackNumber";
NSString *const VLCMetaInformationDescription    = @"description";
NSString *const VLCMetaInformationRating         = @"rating";
NSString *const VLCMetaInformationDate           = @"date";
NSString *const VLCMetaInformationSetting        = @"setting";
NSString *const VLCMetaInformationURL            = @"url";
NSString *const VLCMetaInformationLanguage       = @"language";
NSString *const VLCMetaInformationNowPlaying     = @"nowPlaying";
NSString *const VLCMetaInformationPublisher      = @"publisher";
NSString *const VLCMetaInformationEncodedBy      = @"encodedBy";
NSString *const VLCMetaInformationArtworkURL     = @"artworkURL";
NSString *const VLCMetaInformationArtwork        = @"artwork";
NSString *const VLCMetaInformationTrackID        = @"trackID";

/* Notification Messages */
NSString *const VLCMediaMetaChanged              = @"VLCMediaMetaChanged";

/******************************************************************************
 * @property (readwrite)
 */
@interface VLCMedia ()
@property (readwrite) VLCMediaState state;
@end

/******************************************************************************
 * Interface (Private)
 */
// TODO: Documentation
@interface VLCMedia (Private)
/* Statics */
+ (libvlc_meta_t)stringToMetaType:(NSString *)string;
+ (NSString *)metaTypeToString:(libvlc_meta_t)type;

/* Initializers */
- (void)initInternalMediaDescriptor;

/* Operations */
- (void)fetchMetaInformationFromLibVLCWithType:(NSString*)metaType;
#if !TARGET_OS_IPHONE
- (void)fetchMetaInformationForArtWorkWithURL:(NSString *)anURL;
- (void)setArtwork:(NSImage *)art;
#endif

- (void)parseIfNeeded;

/* Callback Methods */
- (void)parsedChanged:(NSNumber *)isParsedAsNumber;
- (void)metaChanged:(NSString *)metaType;
- (void)subItemAdded;
- (void)setStateAsNumber:(NSNumber *)newStateAsNumber;
@end

static VLCMediaState libvlc_state_to_media_state[] =
{
    [libvlc_NothingSpecial] = VLCMediaStateNothingSpecial,
    [libvlc_Stopped]        = VLCMediaStateNothingSpecial,
    [libvlc_Opening]        = VLCMediaStateNothingSpecial,
    [libvlc_Buffering]      = VLCMediaStateBuffering,
    [libvlc_Ended]          = VLCMediaStateNothingSpecial,
    [libvlc_Error]          = VLCMediaStateError,
    [libvlc_Playing]        = VLCMediaStatePlaying,
    [libvlc_Paused]         = VLCMediaStatePlaying,
};

static inline VLCMediaState LibVLCStateToMediaState( libvlc_state_t state )
{
    return libvlc_state_to_media_state[state];
}

/******************************************************************************
 * LibVLC Event Callback
 */
static void HandleMediaMetaChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(metaChanged:)
                                       withArgumentAsObject:[VLCMedia metaTypeToString:event->u.media_meta_changed.meta_type]];
    [pool release];
}

static void HandleMediaDurationChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(setLength:)
                                       withArgumentAsObject:[VLCTime timeWithNumber:
                                           @(event->u.media_duration_changed.new_duration)]];
    [pool release];
}

static void HandleMediaStateChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(setStateAsNumber:)
                                       withArgumentAsObject:@(LibVLCStateToMediaState(event->u.media_state_changed.new_state))];
    [pool release];
}

static void HandleMediaSubItemAdded(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(subItemAdded)
                                       withArgumentAsObject:nil];
    [pool release];
}

static void HandleMediaParsedChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(parsedChanged:)
                                       withArgumentAsObject:@((BOOL)event->u.media_parsed_changed.new_status)];
    [pool release];
}


/******************************************************************************
 * Implementation
 */
@implementation VLCMedia
+ (id)mediaWithURL:(NSURL *)anURL;
{
    return [[[VLCMedia alloc] initWithURL:anURL] autorelease];
}

+ (id)mediaWithPath:(NSString *)aPath;
{
    return [[[VLCMedia alloc] initWithPath:aPath] autorelease];
}

+ (id)mediaAsNodeWithName:(NSString *)aName;
{
    return [[[VLCMedia alloc] initAsNodeWithName:aName] autorelease];
}

- (id)initWithPath:(NSString *)aPath
{
    return [self initWithURL:[NSURL fileURLWithPath:aPath isDirectory:NO]];
}

- (id)initWithURL:(NSURL *)anURL
{
    if (self = [super init]) {
        VLCLibrary *library = [VLCLibrary sharedLibrary];
        NSAssert(library.instance, @"no library instance when creating media");

        p_md = libvlc_media_new_location(library.instance, [[anURL absoluteString] UTF8String]);

        delegate = nil;
        metaDictionary = [[NSMutableDictionary alloc] initWithCapacity:3];

        // This value is set whenever the demuxer figures out what the length is.
        // TODO: Easy way to tell the length of the movie without having to instiate the demuxer.  Maybe cached info?
        length = nil;

        [self initInternalMediaDescriptor];
    }
    return self;
}

- (id)initAsNodeWithName:(NSString *)aName
{
    if (self = [super init]) {
        p_md = libvlc_media_new_as_node([VLCLibrary sharedInstance],
                                                   [aName UTF8String]);

        delegate = nil;
        metaDictionary = [[NSMutableDictionary alloc] initWithCapacity:3];

        // This value is set whenever the demuxer figures out what the length is.
        // TODO: Easy way to tell the length of the movie without having to instiate the demuxer.  Maybe cached info?
        length = nil;

        [self initInternalMediaDescriptor];
    }
    return self;
}

- (void)dealloc
{
    libvlc_event_manager_t * p_em = libvlc_media_event_manager(p_md);
    libvlc_event_detach(p_em, libvlc_MediaMetaChanged,     HandleMediaMetaChanged,     self);
    libvlc_event_detach(p_em, libvlc_MediaDurationChanged, HandleMediaDurationChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaStateChanged,    HandleMediaStateChanged,    self);
    libvlc_event_detach(p_em, libvlc_MediaSubItemAdded,    HandleMediaSubItemAdded,    self);
    libvlc_event_detach(p_em, libvlc_MediaParsedChanged,   HandleMediaParsedChanged,   self);
    [[VLCEventManager sharedManager] cancelCallToObject:self];

    // Testing to see if the pointer exists is not required, if the pointer is null
    // then the release message is not sent to it.
    delegate = nil;
    [length release];
    [url release];
    [subitems release];
    [metaDictionary release];

    libvlc_media_release( p_md );

    [super dealloc];
}

- (NSString *)description
{
    NSString * result = metaDictionary[VLCMetaInformationTitle];
    return [NSString stringWithFormat:@"<%@ %p> %@", [self class], self, (result ? result : [url absoluteString])];
}

- (NSComparisonResult)compare:(VLCMedia *)media
{
    if (self == media)
        return NSOrderedSame;
    if (!media)
        return NSOrderedDescending;
    return p_md == [media libVLCMediaDescriptor] ? NSOrderedSame : NSOrderedAscending;
}

@synthesize delegate;

- (VLCTime *)length
{
    if (!length) {
        // Try figuring out what the length is
        long long duration = libvlc_media_get_duration( p_md );
        if (duration > -1) {
            length = [[VLCTime timeWithNumber:@(duration)] retain];
            return [[length retain] autorelease];
        }
        return [VLCTime nullTime];
    }
    return [[length retain] autorelease];
}

- (VLCTime *)lengthWaitUntilDate:(NSDate *)aDate
{
    static const long long thread_sleep = 10000;

    if (!length) {
        // Force parsing of this item.
        [self parseIfNeeded];

        // wait until we are preparsed
        while (!length && !libvlc_media_is_parsed(p_md) && [aDate timeIntervalSinceNow] > 0)
            usleep( thread_sleep );

        // So we're done waiting, but sometimes we trap the fact that the parsing
        // was done before the length gets assigned, so lets go ahead and assign
        // it ourselves.
        if (!length)
            return [self length];
    }

    return [[length retain] autorelease];
}

- (BOOL)isParsed
{
    return isParsed;
}

- (void)parse
{
    if (p_md)
        libvlc_media_parse_async(p_md);
}

- (void)synchronousParse
{
    if (p_md)
        libvlc_media_parse(p_md);
}

- (void)addOptions:(NSDictionary*)options
{
    if (p_md) {
        for (NSString * key in [options allKeys]) {
            if (options[key] != [NSNull null])
                libvlc_media_add_option(p_md, [[NSString stringWithFormat:@"%@=%@", key, options[key]] UTF8String]);
            else
                libvlc_media_add_option(p_md, [[NSString stringWithFormat:@"%@", key] UTF8String]);
        }
    }
}

- (NSDictionary*) stats
{
    if (!p_md)
        return NULL;

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    d[@"demuxBitrate"] = @(p_stats.f_demux_bitrate);
    d[@"inputBitrate"] = @(p_stats.f_input_bitrate);
    d[@"sendBitrate"] = @(p_stats.f_send_bitrate);
    d[@"decodedAudio"] = @(p_stats.i_decoded_audio);
    d[@"decodedVideo"] = @(p_stats.i_decoded_video);
    d[@"demuxCorrupted"] = @(p_stats.i_demux_corrupted);
    d[@"demuxDiscontinuity"] = @(p_stats.i_demux_discontinuity);
    d[@"demuxReadBytes"] = @(p_stats.i_demux_read_bytes);
    d[@"displayedPictures"] = @(p_stats.i_displayed_pictures);
    d[@"lostAbuffers"] = @(p_stats.i_lost_abuffers);
    d[@"lostPictures"] = @(p_stats.i_lost_pictures);
    d[@"playedAbuffers"] = @(p_stats.i_played_abuffers);
    d[@"readBytes"] = @(p_stats.i_read_bytes);
    d[@"sentBytes"] = @(p_stats.i_sent_bytes);
    d[@"sentPackets"] = @(p_stats.i_sent_packets);

    return d;
}

- (NSInteger)numberOfReadBytesOnInput
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_read_bytes;
}

- (float)inputBitrate
{
    if (!p_md)
        return .0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.f_input_bitrate;
}

- (NSInteger)numberOfReadBytesOnDemux
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_demux_read_bytes;
}

- (float)demuxBitrate
{
    if (!p_md)
        return .0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.f_demux_bitrate;
}

- (NSInteger)numberOfDecodedVideoBlocks
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_decoded_video;
}

- (NSInteger)numberOfDecodedAudioBlocks
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_decoded_audio;
}

- (NSInteger)numberOfDisplayedPictures
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_displayed_pictures;
}

- (NSInteger)numberOfLostPictures
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_lost_pictures;
}

- (NSInteger)numberOfPlayedAudioBuffers
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_played_abuffers;
}

- (NSInteger)numberOfLostAudioBuffers
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_lost_abuffers;
}

- (NSInteger)numberOfSentPackets
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_sent_packets;
}

- (NSInteger)numberOfSentBytes
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_sent_bytes;
}

- (float)streamOutputBitrate
{
    if (!p_md)
        return .0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.f_send_bitrate;
}

- (NSInteger)numberOfCorruptedDataPackets
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_demux_corrupted;
}

- (NSInteger)numberOfDiscontinuties
{
    if (!p_md)
        return 0;

    libvlc_media_stats_t p_stats;
    libvlc_media_get_stats(p_md, &p_stats);

    return p_stats.i_demux_discontinuity;
}

NSString *const VLCMediaTracksInformationCodec = @"codec"; // NSNumber
NSString *const VLCMediaTracksInformationId    = @"id";    // NSNumber
NSString *const VLCMediaTracksInformationType  = @"type";  // NSString

NSString *const VLCMediaTracksInformationCodecProfile  = @"profile"; // NSNumber
NSString *const VLCMediaTracksInformationCodecLevel    = @"level";   // NSNumber

NSString *const VLCMediaTracksInformationTypeAudio    = @"audio";
NSString *const VLCMediaTracksInformationTypeVideo    = @"video";
NSString *const VLCMediaTracksInformationTypeText     = @"text";
NSString *const VLCMediaTracksInformationTypeUnknown  = @"unknown";

NSString *const VLCMediaTracksInformationBitrate      = @"bitrate"; // NSNumber
NSString *const VLCMediaTracksInformationLanguage     = @"language"; // NSString
NSString *const VLCMediaTracksInformationDescription  = @"description"; // NSString

NSString *const VLCMediaTracksInformationAudioChannelsNumber = @"channelsNumber"; // NSNumber
NSString *const VLCMediaTracksInformationAudioRate           = @"rate";           // NSNumber

NSString *const VLCMediaTracksInformationVideoHeight = @"height"; // NSNumber
NSString *const VLCMediaTracksInformationVideoWidth  = @"width";  // NSNumber

NSString *const VLCMediaTracksInformationSourceAspectRatio        = @"sar_num"; // NSNumber
NSString *const VLCMediaTracksInformationSourceAspectDenominator  = @"sar_den";  // NSNumber

NSString *const VLCMediaTracksInformationFrameRate             = @"frame_rate_num"; // NSNumber
NSString *const VLCMediaTracksInformationFrameRateDenominator  = @"frame_rate_den";  // NSNumber

NSString *const VLCMediaTracksInformationTextEncoding = @"encoding"; // NSString

- (NSArray *)tracksInformation
{
    [self synchronousParse];

    libvlc_media_track_t **tracksInfo;
    unsigned int count = libvlc_media_tracks_get(p_md, &tracksInfo);
    NSMutableArray *array = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                           @(tracksInfo[i]->i_codec),
                                           VLCMediaTracksInformationCodec,
                                           @(tracksInfo[i]->i_id),
                                           VLCMediaTracksInformationId,
                                           @(tracksInfo[i]->i_profile),
                                           VLCMediaTracksInformationCodecProfile,
                                           @(tracksInfo[i]->i_level),
                                           VLCMediaTracksInformationCodecLevel,
                                           @(tracksInfo[i]->i_bitrate),
                                           VLCMediaTracksInformationBitrate,
                                           nil];
        if (tracksInfo[i]->psz_language)
            dictionary[VLCMediaTracksInformationLanguage] = [NSString stringWithFormat:@"%s",tracksInfo[i]->psz_language];

        if (tracksInfo[i]->psz_description)
            dictionary[VLCMediaTracksInformationDescription] = [NSString stringWithFormat:@"%s",tracksInfo[i]->psz_description];

        NSString *type;
        switch (tracksInfo[i]->i_type) {
            case libvlc_track_audio:
                type = VLCMediaTracksInformationTypeAudio;
                dictionary[VLCMediaTracksInformationAudioChannelsNumber] = @(tracksInfo[i]->audio->i_channels);
                dictionary[VLCMediaTracksInformationAudioRate] = @(tracksInfo[i]->audio->i_rate);
                break;
            case libvlc_track_video:
                type = VLCMediaTracksInformationTypeVideo;
                dictionary[VLCMediaTracksInformationVideoWidth] = @(tracksInfo[i]->video->i_width);
                dictionary[VLCMediaTracksInformationVideoHeight] = @(tracksInfo[i]->video->i_height);
                dictionary[VLCMediaTracksInformationSourceAspectRatio] = @(tracksInfo[i]->video->i_sar_num);
                dictionary[VLCMediaTracksInformationSourceAspectDenominator] = @(tracksInfo[i]->video->i_sar_den);
                dictionary[VLCMediaTracksInformationFrameRate] = @(tracksInfo[i]->video->i_frame_rate_num);
                dictionary[VLCMediaTracksInformationFrameRateDenominator] = @(tracksInfo[i]->video->i_frame_rate_den);
                break;
            case libvlc_track_text:
                type = VLCMediaTracksInformationTypeText;
                if (tracksInfo[i]->subtitle->psz_encoding)
                    dictionary[VLCMediaTracksInformationTextEncoding] = [NSString stringWithFormat:@"%s", tracksInfo[i]->subtitle->psz_encoding];
                break;
            case libvlc_track_unknown:
            default:
                type = VLCMediaTracksInformationTypeUnknown;
                break;
        }
        [dictionary setValue:type forKey:VLCMediaTracksInformationType];

        [array addObject:dictionary];
    }
    libvlc_media_tracks_release(tracksInfo, count);
    return array;
}

- (BOOL)isMediaSizeSuitableForDevice
{
#if TARGET_OS_IPHONE
    // Trigger parsing if needed
    if (![self isParsed])
        [self synchronousParse];

    NSUInteger biggestWidth = 0;
    NSUInteger biggestHeight = 0;
    libvlc_media_track_t **tracksInfo;
    unsigned int count = libvlc_media_tracks_get(p_md, &tracksInfo);
    for (NSUInteger i = 0; i < count; i++) {
        switch (tracksInfo[i]->i_type) {
            case libvlc_track_video:
                if (tracksInfo[i]->video->i_width > biggestWidth)
                    biggestWidth = tracksInfo[i]->video->i_width;
                if (tracksInfo[i]->video->i_height > biggestHeight)
                    biggestHeight = tracksInfo[i]->video->i_height;
                break;
            default:
                break;
        }
    }

    if (biggestHeight > 0 && biggestWidth > 0) {
        size_t size;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);

        char *answer = malloc(size);
        sysctlbyname("hw.machine", answer, &size, NULL, 0);

        NSString *currentMachine = @(answer);
        free(answer);

        NSUInteger totalNumberOfPixels = biggestWidth * biggestHeight;

        if ([currentMachine hasPrefix:@"iPhone2"] || [currentMachine hasPrefix:@"iPhone3"] || [currentMachine hasPrefix:@"iPad1"] || [currentMachine hasPrefix:@"iPod3"] || [currentMachine hasPrefix:@"iPod4"]) {
            // iPhone 3GS, iPhone 4, first gen. iPad, 3rd and 4th generation iPod touch
            return (totalNumberOfPixels < 600000); // between 480p and 720p
        } else if ([currentMachine hasPrefix:@"iPhone4"] || [currentMachine hasPrefix:@"iPad3,1"] || [currentMachine hasPrefix:@"iPad3,2"] || [currentMachine hasPrefix:@"iPad3,3"] || [currentMachine hasPrefix:@"iPod4"] || [currentMachine hasPrefix:@"iPad2"] || [currentMachine hasPrefix:@"iPod5"]) {
            // iPhone 4S, iPad 2 and 3, iPod 4 and 5
            return (totalNumberOfPixels < 922000); // 720p
        } else {
            // iPhone 5, iPad 4
            return (totalNumberOfPixels < 2074000); // 1080p
        }
    }
#endif

    return YES;
}

@synthesize url;
@synthesize subitems;


- (NSString *)metadataForKey:(NSString *)key
{
    if (!p_md)
        return NULL;

    if (![self isParsed])
        [self synchronousParse];

    char *returnValue = libvlc_media_get_meta(p_md, [VLCMedia stringToMetaType:key]);

    if (!returnValue)
        return NULL;

    NSString *actualReturnValue = [NSString stringWithUTF8String:returnValue];
    free(returnValue);

    return actualReturnValue;
}

- (void)setMetadata:(NSString *)data forKey:(NSString *)key
{
    if (!p_md)
        return;

    libvlc_media_set_meta(p_md, [VLCMedia stringToMetaType:key], [data UTF8String]);
}

- (BOOL)saveMetadata
{
    if (p_md)
        return libvlc_media_save_meta(p_md);

    return NO;
}

@synthesize metaDictionary;
@synthesize state;

@end

/******************************************************************************
 * Implementation VLCMedia (LibVLCBridging)
 */
@implementation VLCMedia (LibVLCBridging)

+ (id)mediaWithLibVLCMediaDescriptor:(void *)md
{
    return [[[VLCMedia alloc] initWithLibVLCMediaDescriptor:md] autorelease];
}

- (id)initWithLibVLCMediaDescriptor:(void *)md
{
    if (self = [super init]) {
        libvlc_media_retain(md);
        p_md = md;

        metaDictionary = [[NSMutableDictionary alloc] initWithCapacity:3];
        [self initInternalMediaDescriptor];
    }
    return self;
}

- (void *)libVLCMediaDescriptor
{
    return p_md;
}

+ (id)mediaWithMedia:(VLCMedia *)media andLibVLCOptions:(NSDictionary *)options
{
    libvlc_media_t * p_md;
    p_md = libvlc_media_duplicate([media libVLCMediaDescriptor]);

    for (NSString * key in [options allKeys]) {
        if (options[key] != [NSNull null])
            libvlc_media_add_option(p_md, [[NSString stringWithFormat:@"%@=%@", key, options[key]] UTF8String]);
        else
            libvlc_media_add_option(p_md, [[NSString stringWithFormat:@"%@", key] UTF8String]);

    }
    return [VLCMedia mediaWithLibVLCMediaDescriptor:p_md];
}

@end

/******************************************************************************
 * Implementation VLCMedia (Private)
 */
@implementation VLCMedia (Private)

+ (libvlc_meta_t)stringToMetaType:(NSString *)string
{
    static NSDictionary * stringToMetaDictionary = nil;
    // TODO: Thread safe-ize
    if (!stringToMetaDictionary) {
#define VLCStringToMeta( name ) [NSNumber numberWithInt: libvlc_meta_##name], VLCMetaInformation##name
        stringToMetaDictionary =
            [[NSDictionary dictionaryWithObjectsAndKeys:
                VLCStringToMeta(Title),
                VLCStringToMeta(Artist),
                VLCStringToMeta(Genre),
                VLCStringToMeta(Copyright),
                VLCStringToMeta(Album),
                VLCStringToMeta(TrackNumber),
                VLCStringToMeta(Description),
                VLCStringToMeta(Rating),
                VLCStringToMeta(Date),
                VLCStringToMeta(Setting),
                VLCStringToMeta(URL),
                VLCStringToMeta(Language),
                VLCStringToMeta(NowPlaying),
                VLCStringToMeta(Publisher),
                VLCStringToMeta(ArtworkURL),
                VLCStringToMeta(TrackID),
                nil] retain];
#undef VLCStringToMeta
    }
    NSNumber * number = stringToMetaDictionary[string];
    return number ? [number intValue] : -1;
}

+ (NSString *)metaTypeToString:(libvlc_meta_t)type
{
#define VLCMetaToString( name, type )   if (libvlc_meta_##name == type) return VLCMetaInformation##name;
    VLCMetaToString(Title, type);
    VLCMetaToString(Artist, type);
    VLCMetaToString(Genre, type);
    VLCMetaToString(Copyright, type);
    VLCMetaToString(Album, type);
    VLCMetaToString(TrackNumber, type);
    VLCMetaToString(Description, type);
    VLCMetaToString(Rating, type);
    VLCMetaToString(Date, type);
    VLCMetaToString(Setting, type);
    VLCMetaToString(URL, type);
    VLCMetaToString(Language, type);
    VLCMetaToString(NowPlaying, type);
    VLCMetaToString(Publisher, type);
    VLCMetaToString(ArtworkURL, type);
    VLCMetaToString(TrackID, type);
#undef VLCMetaToString
    return nil;
}

- (void)initInternalMediaDescriptor
{
    char * p_url = libvlc_media_get_mrl( p_md );
    if (!p_url)
        return;

    url = [[NSURL URLWithString:@(p_url)] retain];
    if (!url) /* Attempt to interpret as a file path then */
        url = [[NSURL fileURLWithPath:@(p_url)] retain];
    free(p_url);

    libvlc_media_set_user_data(p_md, (void*)self);

    libvlc_event_manager_t * p_em = libvlc_media_event_manager( p_md );
    libvlc_event_attach(p_em, libvlc_MediaMetaChanged,     HandleMediaMetaChanged,     self);
    libvlc_event_attach(p_em, libvlc_MediaDurationChanged, HandleMediaDurationChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaStateChanged,    HandleMediaStateChanged,    self);
    libvlc_event_attach(p_em, libvlc_MediaSubItemAdded,    HandleMediaSubItemAdded,    self);
    libvlc_event_attach(p_em, libvlc_MediaParsedChanged,   HandleMediaParsedChanged,   self);

    libvlc_media_list_t * p_mlist = libvlc_media_subitems( p_md );

    if (!p_mlist)
        subitems = nil;
    else {
        subitems = [[VLCMediaList mediaListWithLibVLCMediaList:p_mlist] retain];
        libvlc_media_list_release( p_mlist );
    }

    isParsed = libvlc_media_is_parsed(p_md);
    state = LibVLCStateToMediaState(libvlc_media_get_state( p_md ));
}

- (void)fetchMetaInformationFromLibVLCWithType:(NSString *)metaType
{
    char * psz_value = libvlc_media_get_meta( p_md, [VLCMedia stringToMetaType:metaType] );
    NSString * newValue = psz_value ? @(psz_value) : nil;
    NSString * oldValue = [metaDictionary valueForKey:metaType];
    free(psz_value);

    if (newValue != oldValue && !(oldValue && newValue && [oldValue compare:newValue] == NSOrderedSame)) {
        // Only fetch the art if needed. (ie, create the NSImage, if it was requested before)
        if (isArtFetched && [metaType isEqualToString:VLCMetaInformationArtworkURL]) {
            [NSThread detachNewThreadSelector:@selector(fetchMetaInformationForArtWorkWithURL:)
                                         toTarget:self
                                       withObject:newValue];
        }

        [metaDictionary setValue:newValue forKeyPath:metaType];
    }
}

#if !TARGET_OS_IPHONE
- (void)fetchMetaInformationForArtWorkWithURL:(NSString *)anURL
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    NSImage * art = nil;

    if (anURL) {
        // Go ahead and load up the art work
        NSURL * artUrl = [NSURL URLWithString:[anURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        // Don't attempt to fetch artwork from remote. Core will do that alone
        if ([artUrl isFileURL])
            art  = [[[NSImage alloc] initWithContentsOfURL:artUrl] autorelease];
    }

    // If anything was found, lets save it to the meta data dictionary
    [self performSelectorOnMainThread:@selector(setArtwork:) withObject:art waitUntilDone:NO];

    [pool release];
}

- (void)setArtwork:(NSImage *)art
{
    if (!art) {
        [metaDictionary removeObjectForKey:@"artwork"];
        return;
    }

    [metaDictionary setObject:art forKey:@"artwork"];
}
#endif

- (void)parseIfNeeded
{
    if (![self isParsed])
        [self parse];
}

- (void)metaChanged:(NSString *)metaType
{
    [self fetchMetaInformationFromLibVLCWithType:metaType];

    if ([delegate respondsToSelector:@selector(mediaMetaDataDidChange:)])
        [self.delegate mediaMetaDataDidChange:self];
}

- (void)subItemAdded
{
    if (subitems)
        return; /* Nothing to do */

    libvlc_media_list_t * p_mlist = libvlc_media_subitems( p_md );

    NSAssert( p_mlist, @"The mlist shouldn't be nil, we are receiving a subItemAdded");

    [self willChangeValueForKey:@"subitems"];
    subitems = [[VLCMediaList mediaListWithLibVLCMediaList:p_mlist] retain];
    [self didChangeValueForKey:@"subitems"];
    libvlc_media_list_release( p_mlist );
}

- (void)parsedChanged:(NSNumber *)isParsedAsNumber
{
    [self willChangeValueForKey:@"parsed"];
    isParsed = [isParsedAsNumber boolValue];
    [self didChangeValueForKey:@"parsed"];

    // FIXME: Probably don't even call this if there is no delegate.
    if (!delegate || !isParsed)
        return;

    if ([delegate respondsToSelector:@selector(mediaDidFinishParsing:)])
        [delegate mediaDidFinishParsing:self];
}

- (void)setStateAsNumber:(NSNumber *)newStateAsNumber
{
    [self setState: [newStateAsNumber intValue]];
}

#if TARGET_OS_IPHONE
- (NSDictionary *)metaDictionary
{
    if (!areOthersMetaFetched) {
        areOthersMetaFetched = YES;

        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationTitle];
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationArtist];
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationAlbum];
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationDate];
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationGenre];
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationTrackNumber];
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationNowPlaying];
    }
    if (!isArtURLFetched) {
        isArtURLFetched = YES;
        /* Force isArtURLFetched, that will trigger artwork download eventually
         * And all the other meta will be added through the libvlc event system */
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationArtworkURL];
    }
    return metaDictionary;
}

#else

- (id)valueForKeyPath:(NSString *)keyPath
{
    if (!isArtFetched && [keyPath isEqualToString:@"metaDictionary.artwork"]) {
        isArtFetched = YES;
        /* Force the retrieval of the artwork now that someone asked for it */
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationArtworkURL];
    } else if (!areOthersMetaFetched && [keyPath hasPrefix:@"metaDictionary."]) {
        areOthersMetaFetched = YES;
        /* Force VLCMetaInformationTitle, that will trigger preparsing
         * And all the other meta will be added through the libvlc event system */
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationTitle];
    } else if (!isArtURLFetched && [keyPath hasPrefix:@"metaDictionary.artworkURL"]) {
        isArtURLFetched = YES;
        /* Force isArtURLFetched, that will trigger artwork download eventually
         * And all the other meta will be added through the libvlc event system */
        [self fetchMetaInformationFromLibVLCWithType: VLCMetaInformationArtworkURL];
    }
    return [super valueForKeyPath:keyPath];
}
#endif
@end

/******************************************************************************
 * Implementation VLCMedia (VLCMediaPlayerBridging)
 */

@implementation VLCMedia (VLCMediaPlayerBridging)

- (void)setLength:(VLCTime *)value
{
    if (length && value && [length compare:value] == NSOrderedSame)
        return;

    [length release];
    length = value ? [value retain] : nil;
}

@end
