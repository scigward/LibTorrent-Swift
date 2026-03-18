//
//  TorrentPeerInfo.h
//  LibTorrent
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(TorrentHandle.PeerInfo)
@interface TorrentPeerInfo : NSObject
/// Remote peer IP address string
@property (readonly, strong, nonatomic) NSString *ip;
/// Remote peer port
@property (readonly, nonatomic) NSInteger port;
/// Peer client software name and version
@property (readonly, strong, nonatomic) NSString *client;
/// Peer download progress [0.0 - 1.0]
@property (readonly, nonatomic) float progress;
/// Total bytes downloaded from this peer
@property (readonly, nonatomic) int64_t totalDownload;
/// Total bytes uploaded to this peer
@property (readonly, nonatomic) int64_t totalUpload;
/// Current download speed from this peer (bytes/sec)
@property (readonly, nonatomic) int downSpeed;
/// Current upload speed to this peer (bytes/sec)
@property (readonly, nonatomic) int upSpeed;
/// Peer payload download speed (bytes/sec)
@property (readonly, nonatomic) int payloadDownSpeed;
/// Peer payload upload speed (bytes/sec)
@property (readonly, nonatomic) int payloadUpSpeed;
/// Whether this peer is a seed (has all pieces)
@property (readonly, nonatomic) BOOL isSeed;
/// Whether the connection was incoming (peer connected to us)
@property (readonly, nonatomic) BOOL isIncoming;
/// Whether this connection uses uTP transport
@property (readonly, nonatomic) BOOL isUTP;
/// Whether this connection uses encryption (RC4 or handshake)
@property (readonly, nonatomic) BOOL isEncrypted;
/// Connection type: 0=standard_bittorrent, 1=web_seed, 2=http_seed
@property (readonly, nonatomic) int connectionType;
/// Seconds since the last time we exchanged data with this peer.
/// Corresponds to Hayase's PeerInfo.time.
@property (readonly, nonatomic) NSTimeInterval lastActive;
@end

NS_ASSUME_NONNULL_END
