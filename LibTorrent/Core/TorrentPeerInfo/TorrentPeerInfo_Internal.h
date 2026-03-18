//
//  TorrentPeerInfo_Internal.h
//  LibTorrent
//

#import "TorrentPeerInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface TorrentPeerInfo ()
@property (readwrite, strong, nonatomic) NSString *ip;
@property (readwrite, nonatomic) NSInteger port;
@property (readwrite, strong, nonatomic) NSString *client;
@property (readwrite, nonatomic) float progress;
@property (readwrite, nonatomic) int64_t totalDownload;
@property (readwrite, nonatomic) int64_t totalUpload;
@property (readwrite, nonatomic) int downSpeed;
@property (readwrite, nonatomic) int upSpeed;
@property (readwrite, nonatomic) int payloadDownSpeed;
@property (readwrite, nonatomic) int payloadUpSpeed;
@property (readwrite, nonatomic) BOOL isSeed;
@property (readwrite, nonatomic) BOOL isIncoming;
@property (readwrite, nonatomic) BOOL isUTP;
@property (readwrite, nonatomic) BOOL isEncrypted;
@property (readwrite, nonatomic) int connectionType;
@end

NS_ASSUME_NONNULL_END
