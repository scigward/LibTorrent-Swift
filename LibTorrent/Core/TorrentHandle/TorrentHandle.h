//
//  NSObject+TorrentHandle.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>

#import <LibTorrent/TorrentHandleState.h>
#import <LibTorrent/TorrentTracker.h>
#import <LibTorrent/FileEntry.h>
#import <LibTorrent/TorrentPeerInfo.h>

NS_ASSUME_NONNULL_BEGIN

@class Session;
@class StorageModel;

NS_SWIFT_NAME(TorrentHashes)
@interface TorrentHashes : NSObject<NSCopying>
@property (readonly) BOOL hasV1;
@property (readonly) BOOL hasV2;
@property (readonly) NSData *v1;
@property (readonly) NSData *v2;
@property (readonly) NSData *best;
@end

NS_SWIFT_SENDABLE
NS_SWIFT_NAME(TorrentHandle.Snapshot)
@interface TorrentHandleSnapshot : NSObject

@property (readonly) BOOL isValid;
//@property (readonly) NSData *infoHash DEPRECATED_MSG_ATTRIBUTE("Use infoHashes instead");
@property (readonly) TorrentHashes *infoHashes;
@property (readonly) NSString* name;
@property (readonly) TorrentHandleState state;
@property (readonly, nullable) NSString *creator;
@property (readonly, nullable) NSString *comment;
@property (readonly, nullable) NSDate *creationDate;
@property (readonly) double progress;
@property (readonly) double progressWanted;
@property (readonly) NSUInteger numberOfPeers;
@property (readonly) NSUInteger numberOfSeeds;
@property (readonly) NSUInteger numberOfLeechers;
@property (readonly) NSUInteger numberOfTotalPeers;
@property (readonly) NSUInteger numberOfTotalSeeds;
@property (readonly) NSUInteger numberOfTotalLeechers;
@property (readonly) uint64_t downloadRate;
@property (readonly) uint64_t uploadRate;
@property (readonly) BOOL hasMetadata;
@property (readonly) uint64_t total;
@property (readonly) uint64_t totalDone;
@property (readonly) uint64_t totalWanted;
@property (readonly) uint64_t totalWantedDone;
@property (readonly) uint64_t totalDownload;
@property (readonly) uint64_t totalUpload;
@property (readonly) BOOL isPaused;
@property (readonly) BOOL isFinished;
@property (readonly) BOOL isSeed;
@property (readonly) BOOL isSequential;
/// Whether the torrent is marked as private (no PeX or DHT for this torrent).
@property (readonly) BOOL isPrivate;
/// Whether libtorrent is auto-managing this torrent (queuing, seeding decisions).
@property (readonly) BOOL isAutoManaged;
/// Estimated time remaining to complete the download, in seconds.
/// Returns 0 if the download is complete, or -1 if the rate is too low to estimate.
@property (readonly) NSTimeInterval timeRemaining;
/// Seconds the torrent has been in an active (downloading/seeding) state.
/// Corresponds to Hayase's TorrentInfo.time.elapsed.
@property (readonly) NSTimeInterval activeTime;
/// Number of peers in the connection pool not yet connected (DHT/tracker candidates).
/// Hayase's TorrentInfo.peers.wires ≈ numberOfPeers + connectCandidates.
@property (readonly) NSInteger connectCandidates;
/// Current per-torrent download rate limit in bytes per second. 0 = unlimited.
@property (readonly) int downloadLimit;
/// Current per-torrent upload rate limit in bytes per second. 0 = unlimited.
@property (readonly) int uploadLimit;
@property (readonly, nullable) NSArray<NSNumber *> *pieces;
@property (readonly) NSArray<FileEntry *> *files;
@property (readonly) NSArray<TorrentTracker *> *trackers;
@property (readonly) NSString* magnetLink;
@property (readonly, nullable) NSString* torrentFilePath;
@property (readonly, nullable) NSURL* downloadPath;
@property (readonly, nullable) NSUUID* storageUUID;
@property (readonly) BOOL isStorageMissing;
@property (readonly) int pieceLength;
@property (readonly) NSInteger numberOfPieces;
@end

@interface TorrentHandle : NSObject

@property (readonly, nullable) NSUUID* storageUUID;
@property (readonly) TorrentHashes *infoHashes;

@property (readonly) Session* session;
@property (readonly) TorrentHandleSnapshot* snapshot;

- (void)resume;
- (void)pause;
- (void)rehash;
- (void)reload;

- (void)setSequentialDownload:(BOOL)enabled;

/// Enable streaming mode: deselects all pieces (priority 0) and enables sequential download.
/// Only pieces explicitly prioritized will be downloaded. Disable to restore normal download.
- (void)setStreamingMode:(BOOL)enabled;

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex;
- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes;
- (void)setAllFilesPriority:(FilePriority)priority;

- (void)setPiecePriority:(NSInteger)pieceIndex priority:(uint8_t)priority;
/// Set priorities for a contiguous range of pieces starting at startIndex.
- (void)setPiecePriorities:(NSArray<NSNumber *> *)priorities fromIndex:(NSInteger)startIndex;

- (void)setPieceDeadline:(NSInteger)pieceIndex deadline:(int)deadline;
/// Set deadlines for a contiguous range of pieces starting at startIndex.
- (void)setPieceDeadlines:(NSArray<NSNumber *> *)deadlines fromIndex:(NSInteger)startIndex;
- (void)resetPieceDeadline:(NSInteger)pieceIndex;
/// Clear all piece deadlines. Useful when seeking during streaming.
- (void)clearAllPieceDeadlines;

- (void)readPiece:(NSInteger)pieceIndex;
- (void)flushCache;
- (void)forceRecheck;

/// Set per-torrent download rate limit in bytes per second. 0 means unlimited.
- (void)setDownloadLimit:(int)bytesPerSecond;
/// Set per-torrent upload rate limit in bytes per second. 0 means unlimited.
- (void)setUploadLimit:(int)bytesPerSecond;
/// Set per-torrent maximum number of connections. 0 means unlimited.
/// Useful for streaming mode to conserve bandwidth from peer connections.
- (void)setConnectionsLimit:(int)maxConnections;

/// Get per-peer information: IP, speeds, client name, progress, connection flags.
- (NSArray<TorrentPeerInfo *> *)peerInfo;

- (void)addTracker:(NSString *)url;
- (void)removeTrackers:(NSArray<NSString *> *)urls;
- (void)forceReannounce;
- (void)forceReannounce:(int)index;

- (void)updateSnapshot;
@end

NS_ASSUME_NONNULL_END
