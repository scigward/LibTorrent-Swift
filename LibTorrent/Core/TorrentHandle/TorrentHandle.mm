//
//  NSObject+TorrentHandle.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "TorrentHandle_Internal.h"
#import "FileEntry_Internal.h"
#import "TorrentTracker_Internal.h"
#import "TorrentPeerInfo_Internal.h"
#import "Session_Internal.h"

#import "NSData+Hex.h"

#import "libtorrent/torrent_status.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/magnet_uri.hpp"
#import "libtorrent/peer_info.hpp"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation TorrentHashes

#if LIBTORRENT_VERSION_MAJOR > 1
- (instancetype)initWith:(lt::info_hash_t)infoHash {
    self = [self init];
    if (self) {
        _v1 = [[NSData alloc] initWithBytes:infoHash.v1.data() length:infoHash.v1.size()];
        _v2 = [[NSData alloc] initWithBytes:infoHash.v2.data() length:infoHash.v2.size()];
        _hasV1 = infoHash.has_v1();
        _hasV2 = infoHash.has_v2();

        auto best = infoHash.get_best();
        _best = [[NSData alloc] initWithBytes:best.data() length:best.size()]; ;
    }
    return self;
}
#else
- (instancetype)initWith:(lt::sha1_hash)infoHash {
    self = [self init];
    if (self) {
        _v1 = [[NSData alloc] initWithBytes:infoHash.data() length:infoHash.size()];
        _v2 = NULL;
        _hasV1 = true;
        _hasV2 = false;

        _best = _v1;
    }
    return self;
}
#endif

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    } 

    if (![other isKindOfClass:[TorrentHashes class]]) {
        return NO;
    }

    return [self.best isEqual:((TorrentHashes *)other).best];

//    return [self.v1 isEqual:((TorrentHashes *)other).v1] && [self.v2 isEqual:((TorrentHashes *)other).v2];
}

- (NSUInteger)hash {
    return _best.hash;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    TorrentHashes* copy = [[[self class] allocWithZone:zone] init];

        if (copy) {
            copy.v1 = self.v1;
            copy.v2 = self.v2;
            copy.hasV1 = self.hasV1;
            copy.hasV2 = self.hasV2;
            copy.best = self.best;
        }

        return copy;
}

@end

@implementation TorrentHandleSnapshot
@end

@implementation TorrentHandle

- (instancetype)initWith:(lt::torrent_handle)torrentHandle inSession:(Session *)session {
    self = [self init];
    if (self) {
        _session = session;
        _torrentHandle = torrentHandle;
        _torrentPath = session.torrentsPath;
        _sessionDownloadPath = session.downloadPath;
    }
    return self;
}

- (BOOL)isValid {
    return self.torrentHandle.is_valid();
}

- (NSUInteger)hash {
    return self.infoHashes.best.hash;
}

//- (NSData *)infoHash {
//    return [self.infoHashes best];
//}

- (TorrentHashes *)infoHashes {
#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = _torrentHandle.info_hashes();
#else
    auto ih = _torrentHandle.info_hash();
#endif
    return [[TorrentHashes alloc] initWith:ih];
}

- (NSString *)nameFromStatus: (lt::torrent_status)ts {
    return [NSString stringWithCString:ts.name.c_str() encoding: NSUTF8StringEncoding];
}

- (NSString * _Nullable)creatorFromStatus: (lt::torrent_status)ts {
    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return [NSString stringWithCString:info->creator().c_str() encoding: NSUTF8StringEncoding];
    }

    return NULL;
}

- (NSString * _Nullable)commentFromStatus: (lt::torrent_status)ts {
    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return [NSString stringWithCString:info->comment().c_str() encoding: NSUTF8StringEncoding];
    }

    return NULL;
}

- (NSDate * _Nullable)creationDateFromStatus: (lt::torrent_status)ts {
    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return [[NSDate alloc] initWithTimeIntervalSince1970:info->creation_date()];
    }

    return NULL;
}

- (TorrentHandleState)stateFromStatus: (lt::torrent_status)ts {
    switch (ts.state) {
        case lt::torrent_status::state_t::checking_files: return TorrentHandleStateCheckingFiles;
        case lt::torrent_status::state_t::downloading_metadata: return TorrentHandleStateDownloadingMetadata;
        case lt::torrent_status::state_t::downloading: return TorrentHandleStateDownloading;
        case lt::torrent_status::state_t::finished: return TorrentHandleStateFinished;
        case lt::torrent_status::state_t::seeding: return TorrentHandleStateSeeding;
//        case lt::torrent_status::state_t::allocating: return TorrentHandleStateAllocating;
        case lt::torrent_status::state_t::checking_resume_data: return TorrentHandleStateCheckingResumeData;
        default: return TorrentHandleStateCheckingFiles; // This is an error and should never be the case
    }
}

- (double)progressFromStatus: (lt::torrent_status)status {
    return status.progress;
}

- (double)progressWantedFromStatus: (lt::torrent_status)status {
    auto totalWanted = (double) [self totalWantedFromStatus:status];
    if (totalWanted == 0) { return 0; }
    return (double) [self totalWantedDoneFromStatus:status] / totalWanted;
}

- (NSUInteger)numberOfPeersFromStatus: (lt::torrent_status)status {
    return status.num_peers;
}

- (NSUInteger)numberOfSeedsFromStatus: (lt::torrent_status)status {
    return status.num_seeds;
}

- (NSUInteger)numberOfLeechersFromStatus: (lt::torrent_status)status {
    return [self numberOfPeersFromStatus:status] - [self numberOfSeedsFromStatus:status];
}

- (NSUInteger)numberOfTotalPeersFromStatus: (lt::torrent_status)status {
    int peers = status.num_complete + status.num_incomplete;
    return peers > 0 ? peers : status.list_peers;
}

- (NSUInteger)numberOfTotalSeedsFromStatus: (lt::torrent_status)status {
    int complete = status.num_complete;
    return complete > 0 ? complete : status.list_seeds;
}

- (NSUInteger)numberOfTotalLeechersFromStatus: (lt::torrent_status)status {
    int incomplete = status.num_incomplete;
    return incomplete > 0 ? incomplete : status.list_peers - status.list_seeds;
}

- (uint64_t)downloadRateFromStatus: (lt::torrent_status)status {
    return status.download_rate;
}

- (uint64_t)uploadRateFromStatus: (lt::torrent_status)status {
    return status.upload_rate;
}

- (BOOL)hasMetadataFromStatus: (lt::torrent_status)status {
    return status.has_metadata;
}

- (uint64_t)totalFromStatus: (lt::torrent_status)ts {
    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return info->total_size();
    }

    return NULL;
}

- (uint64_t)totalDoneFromStatus: (lt::torrent_status)ts {
    return ts.total_done;
}

- (uint64_t)totalWantedFromStatus: (lt::torrent_status)ts {
    return ts.total_wanted;
}

- (uint64_t)totalWantedDoneFromStatus: (lt::torrent_status)ts {
    return ts.total_wanted_done;
}

- (uint64_t)totalDownloadFromStatus: (lt::torrent_status)ts {
    return ts.total_download;
}

- (uint64_t)totalUploadFromStatus: (lt::torrent_status)ts {
    return ts.total_upload;
}

- (BOOL)isPausedFromStatus: (lt::torrent_status)ts {
    return static_cast<bool>(ts.flags & lt::torrent_flags::paused);
}

- (BOOL)isFinishedFromStatus: (lt::torrent_status)ts {
    return ts.total_wanted == ts.total_wanted_done;
}

- (BOOL)isSeedFromStatus: (lt::torrent_status)ts {
    return ts.is_seeding;
}

- (BOOL)isSequentialFromStatus: (lt::torrent_status)ts {
    return static_cast<bool>(ts.flags & lt::torrent_flags::sequential_download);
}

- (BOOL)isPrivateFromTorrentFile {
    auto ti = _torrentHandle.torrent_file();
    if (ti != nullptr) {
        return ti->priv();
    }
    return NO;
}

- (NSArray<NSNumber *> *)piecesFromStatus: (lt::torrent_status)stat {
    auto info = _torrentHandle.torrent_file().get();

    if (![self hasMetadataFromStatus:stat])
        return NULL;

    auto array = [[NSMutableArray<NSNumber *> alloc] init];
    for (auto i = static_cast<lt::piece_index_t>(0); i < info->end_piece(); i++) {
        [array addObject: [NSNumber numberWithBool: stat.pieces.get_bit(i)]];
    }
    return array;
}

- (NSString *)magnetLink {
    auto uri = lt::make_magnet_uri(_torrentHandle);
    return [NSString stringWithCString:uri.c_str() encoding: NSUTF8StringEncoding];
}

- (NSString *)torrentFilePathFromStatus: (lt::torrent_status)stat {
    if (!self.isValid || ![self hasMetadataFromStatus:stat]) return NULL;

    auto fileInfo = _torrentHandle.torrent_file().get();
    NSString *fileName = [NSString stringWithFormat:@"%s.torrent", fileInfo->name().c_str()];
    NSString *filePath = [_torrentPath stringByAppendingPathComponent:fileName];

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
        return NULL;

    return filePath;
}

- (NSURL *)downloadPathFromStatus: (lt::torrent_status)stat {
    if (!self.isValid || ![self hasMetadataFromStatus:stat]) return NULL;

    auto savePath = stat.save_path;
//    auto url = [NSString stringWithFormat:@"file://%s", savePath.c_str()];
//    return [NSURL URLWithString: url].URLByStandardizingPath;
    auto path = [NSString stringWithUTF8String: savePath.c_str()];
    return [NSURL fileURLWithPath: path];
}

- (BOOL)isStorageMissing {
    if (self.storageUUID == NULL) return false;
    return !_session.storages[self.storageUUID].allowed;
}

//- (StorageModel*) storage {
//    if (self.downloadPath.path == _session.downloadPath) { return NULL; }
//
//    for (StorageModel* storage in _session.storages.allValues) {
//
//    }
//    
//    return NULL;
////        TorrentService.shared.storages.first(where: { $0.value.url.normalized == downloadPath.normalized })?.value
//}

// MARK: - Functions

- (void)resume {
    _torrentHandle.unset_flags(lt::torrent_flags::auto_managed);
    _torrentHandle.resume();
}

- (void)pause {
    _torrentHandle.unset_flags(lt::torrent_flags::auto_managed);
    _torrentHandle.pause();
}

- (void)rehash {
    _torrentHandle.force_recheck();
    _torrentHandle.set_flags(lt::torrent_flags::auto_managed);
}

- (void)reload {
    auto stat = _torrentHandle.status();
    auto torrentFile = [[TorrentFile alloc] initUnsafeWithFileAtURL: [[NSURL alloc] initFileURLWithPath: [self torrentFilePathFromStatus:stat]]]; //torrentFilePath
    _session.session->remove_torrent(_torrentHandle);
    auto newTorrentHandle = [_session addTorrent: torrentFile];
    _torrentHandle = newTorrentHandle.torrentHandle;
    [self updateSnapshot];
}

- (void)setSequentialDownload:(BOOL)enabled {
    if (!_torrentHandle.is_valid()) return;
    
    if (enabled) {
        _torrentHandle.set_flags(lt::torrent_flags::sequential_download);
    } else {
        _torrentHandle.unset_flags(lt::torrent_flags::sequential_download);
    }
    _torrentHandle.save_resume_data();
}

- (void)setStreamingMode:(BOOL)enabled {
    if (!_torrentHandle.is_valid()) return;

    if (enabled) {
        _torrentHandle.set_flags(lt::torrent_flags::sequential_download);

        // Deselect all pieces (priority 0 = don't download)
        auto ti = _torrentHandle.torrent_file();
        if (ti != nullptr) {
            int numPieces = ti->num_pieces();
            for (int i = 0; i < numPieces; i++) {
                auto idx = static_cast<lt::piece_index_t>(i);
                _torrentHandle.piece_priority(idx, lt::dont_download);
            }
        }
    } else {
        _torrentHandle.unset_flags(lt::torrent_flags::sequential_download);

        // Restore all pieces to default priority
        auto ti = _torrentHandle.torrent_file();
        if (ti != nullptr) {
            int numPieces = ti->num_pieces();
            for (int i = 0; i < numPieces; i++) {
                auto idx = static_cast<lt::piece_index_t>(i);
                _torrentHandle.piece_priority(idx, lt::default_priority);
            }
        }
    }
    _torrentHandle.save_resume_data();
}

- (void)setPiecePriority:(NSInteger)pieceIndex priority:(uint8_t)priority {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    auto prio = static_cast<lt::download_priority_t>(priority);
    _torrentHandle.piece_priority(idx, prio);
}

- (void)setPiecePriorities:(NSArray<NSNumber *> *)priorities fromIndex:(NSInteger)startIndex {
    for (NSInteger i = 0; i < priorities.count; i++) {
        auto idx = static_cast<lt::piece_index_t>(static_cast<int>(startIndex + i));
        auto prio = static_cast<lt::download_priority_t>(priorities[i].unsignedCharValue);
        _torrentHandle.piece_priority(idx, prio);
    }
}

- (void)setPieceDeadline:(NSInteger)pieceIndex deadline:(int)deadline {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    _torrentHandle.set_piece_deadline(idx, deadline);
}

- (void)setPieceDeadlines:(NSArray<NSNumber *> *)deadlines fromIndex:(NSInteger)startIndex {
    for (NSInteger i = 0; i < deadlines.count; i++) {
        auto idx = static_cast<lt::piece_index_t>(static_cast<int>(startIndex + i));
        _torrentHandle.set_piece_deadline(idx, deadlines[i].intValue);
    }
}

- (void)resetPieceDeadline:(NSInteger)pieceIndex {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    _torrentHandle.reset_piece_deadline(idx);
}

- (void)clearAllPieceDeadlines {
    _torrentHandle.clear_piece_deadlines();
}

- (void)readPiece:(NSInteger)pieceIndex {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    _torrentHandle.read_piece(idx);
}

- (void)flushCache {
    _torrentHandle.flush_cache();
}

- (void)forceRecheck {
    _torrentHandle.force_recheck();
}

- (void)setDownloadLimit:(int)bytesPerSecond {
    _torrentHandle.set_download_limit(bytesPerSecond);
}

- (void)setUploadLimit:(int)bytesPerSecond {
    _torrentHandle.set_upload_limit(bytesPerSecond);
}

- (void)setConnectionsLimit:(int)maxConnections {
    _torrentHandle.set_max_connections(maxConnections);
}

- (NSArray<TorrentPeerInfo *> *)peerInfo {
    std::vector<lt::peer_info> peers;
    _torrentHandle.get_peer_info(peers);

    NSMutableArray *results = [[NSMutableArray alloc] init];
    for (const auto &peer : peers) {
        TorrentPeerInfo *info = [[TorrentPeerInfo alloc] init];
        info.ip = [NSString stringWithUTF8String:peer.ip.address().to_string().c_str()];
        info.port = peer.ip.port();
        info.client = [NSString stringWithUTF8String:peer.client.c_str()];
        info.progress = peer.progress;
        info.totalDownload = peer.total_download;
        info.totalUpload = peer.total_upload;
        info.downSpeed = peer.down_speed;
        info.upSpeed = peer.up_speed;
        info.payloadDownSpeed = peer.payload_down_speed;
        info.payloadUpSpeed = peer.payload_up_speed;
        info.isSeed = static_cast<bool>(peer.flags & lt::peer_info::seed);
        info.isIncoming = !static_cast<bool>(peer.flags & lt::peer_info::outgoing_connection);
        info.isUTP = static_cast<bool>(peer.flags & lt::peer_info::utp_socket);
        info.isEncrypted = static_cast<bool>(peer.flags & lt::peer_info::rc4_encrypted)
                        || static_cast<bool>(peer.flags & lt::peer_info::plaintext_encrypted);
        info.connectionType = static_cast<int>(peer.connection_type);
        info.lastActive = (NSTimeInterval)peer.last_active;
        [results addObject:info];
    }
    return [results copy];
}

- (NSArray<FileEntry *> *)filesFromStatus: (lt::torrent_status)stat {
    auto th = _torrentHandle;
    NSMutableArray *results = [[NSMutableArray alloc] init];
    auto ti = th.torrent_file();
    if (ti == nullptr) {
//        NSLog(@"No metadata for torrent with name: %s", th.status().name.c_str());
        return [results copy];
    }

    std::vector<int64_t> progresses;
    th.file_progress(progresses);
    auto priorities = th.get_file_priorities();

    auto info = ti.get();
    auto files = info->files();
    const int pieceLength = info->piece_length();
    
    for (int index = 0; index < files.num_files(); index++) {
        auto i = static_cast<lt::file_index_t>(index);
        auto name = std::string(files.file_name(i));
        auto path = files.file_path(i);
        auto size = files.file_size(i);
        uint8_t priority = static_cast<uint8_t>(priorities[index]);

        FileEntry *fileEntry = [[FileEntry alloc] init];
        fileEntry.index = index;
        fileEntry.name = [NSString stringWithUTF8String:name.c_str()];
        fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
        fileEntry.size = size;
        fileEntry.downloaded = progresses[index];
        fileEntry.progress = size > 0 ? (double)progresses[index] / (double)size : 0.0;
        fileEntry.priority = (FilePriority) priority;

        const auto fileSize = files.file_size(i);// > 0 ? files.file_size(i) : 0;
        const auto fileOffset = files.file_offset(i);

        const long long beginIdx = (fileOffset / pieceLength);
        const long long endIdx = ((fileOffset + fileSize) / pieceLength);

        fileEntry.begin_idx = beginIdx;
        fileEntry.end_idx = endIdx;
        fileEntry.num_pieces = (int)(endIdx - beginIdx);
        auto array = [[NSMutableArray<NSNumber *> alloc] init];
        for (int j = 0; j < fileEntry.num_pieces; j++) {
            auto index = static_cast<lt::piece_index_t>(j + (int)beginIdx);
            [array addObject: [NSNumber numberWithBool: stat.pieces.get_bit(index)]];
        }
        fileEntry.pieces = array;

        NSString *ext = fileEntry.name.pathExtension.lowercaseString;
        if (ext.length > 0) {
            if (@available(iOS 14.0, macOS 11.0, *)) {
                UTType *utType = [UTType typeWithFilenameExtension:ext];
                fileEntry.mimeType = utType ? utType.preferredMIMEType : nil;
            }
        }

        [results addObject:fileEntry];
    }
    return [results copy];
}

- (NSArray<TorrentTracker *> *)trackers {
    auto trackers = _torrentHandle.trackers();
    NSMutableArray *results = [[NSMutableArray alloc] init];

    for (auto tracker : trackers) {
        [results addObject: [[TorrentTracker alloc] initWithAnnounceEntry: tracker from: self]];
    }

    return results;
}

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {
    auto ltIndex = static_cast<lt::file_index_t>((int)fileIndex);
    auto ltPriority = static_cast<lt::download_priority_t>(priority);

    _torrentHandle.file_priority(std::move(ltIndex), std::move(ltPriority));
    _torrentHandle.save_resume_data();
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    auto priorities = _torrentHandle.get_file_priorities();
    for (int i = 0; i < fileIndexes.count; i++) {
        int index = (int)fileIndexes[i].integerValue;
        priorities[index] = static_cast<lt::download_priority_t>(priority);
    }
    _torrentHandle.prioritize_files(priorities);
    _torrentHandle.save_resume_data();
}

- (void)setAllFilesPriority:(FilePriority)priority {
    std::vector<lt::download_priority_t> array;
    for (int i = 0; i < _torrentHandle.torrent_file().get()->files().num_files(); i++) {
        array.push_back(static_cast<lt::download_priority_t>(priority));
    }
    _torrentHandle.prioritize_files(array);
    _torrentHandle.save_resume_data();
}

- (void)addTracker:(NSString *)url {
    _torrentHandle.add_tracker(lt::announce_entry(url.UTF8String));
}

- (void)removeTrackers:(NSArray<NSString *> *)urls {
    auto trackers = _torrentHandle.trackers();
    std::vector<lt::announce_entry> newTrackers;

    for (auto tracker: trackers) {
        if ([urls containsObject: [NSString stringWithFormat:@"%s", tracker.url.c_str()]]) { continue; }
        newTrackers.push_back(tracker);
    }

    _torrentHandle.replace_trackers(newTrackers);
    _torrentHandle.force_reannounce();
}

- (void)forceReannounce {
    [self forceReannounce: -1];
}

- (void)forceReannounce:(int)index {
    _torrentHandle.force_reannounce(0, index);
}

- (void)updateSnapshot {
    if (!self.isValid) return;

    auto snapshot = [[TorrentHandleSnapshot alloc] init];
    try {
        auto stat = _torrentHandle.status();

        snapshot.isValid = self.isValid;
        snapshot.infoHashes = self.infoHashes;
        snapshot.name = [self nameFromStatus:stat];
        snapshot.state = [self stateFromStatus:stat];
        snapshot.creator = [self creatorFromStatus:stat];
        snapshot.comment = [self commentFromStatus:stat];
        snapshot.creationDate = [self creationDateFromStatus:stat];
        snapshot.progress = [self progressFromStatus:stat];
        snapshot.progressWanted = [self progressWantedFromStatus:stat];
        snapshot.numberOfPeers = [self numberOfPeersFromStatus:stat];
        snapshot.numberOfSeeds = [self numberOfSeedsFromStatus:stat];
        snapshot.numberOfLeechers = [self numberOfLeechersFromStatus:stat];
        snapshot.numberOfTotalPeers = [self numberOfTotalPeersFromStatus:stat];
        snapshot.numberOfTotalSeeds = [self numberOfTotalSeedsFromStatus:stat];
        snapshot.numberOfTotalLeechers = [self numberOfTotalLeechersFromStatus:stat];
        snapshot.downloadRate = [self downloadRateFromStatus:stat];
        snapshot.uploadRate = [self uploadRateFromStatus:stat];
        snapshot.hasMetadata = [self hasMetadataFromStatus:stat];
        snapshot.total = [self totalFromStatus:stat];
        snapshot.totalDone = [self totalDoneFromStatus:stat];
        snapshot.totalWanted = [self totalWantedFromStatus:stat];
        snapshot.totalWantedDone = [self totalWantedDoneFromStatus:stat];
        snapshot.totalDownload = [self totalDownloadFromStatus:stat];
        snapshot.totalUpload = [self totalUploadFromStatus:stat];
        snapshot.isPaused = [self isPausedFromStatus:stat];
        snapshot.isFinished = [self isFinishedFromStatus:stat];
        snapshot.isSeed = [self isSeedFromStatus:stat];
        snapshot.isSequential = [self isSequentialFromStatus:stat];
        snapshot.isPrivate = [self isPrivateFromTorrentFile];
        snapshot.isAutoManaged = static_cast<bool>(stat.flags & lt::torrent_flags::auto_managed);
        snapshot.activeTime = (NSTimeInterval)stat.active_time;
        snapshot.connectCandidates = stat.connect_candidates;
        snapshot.downloadLimit = _torrentHandle.download_limit();
        snapshot.uploadLimit = _torrentHandle.upload_limit();

        // Compute ETA
        uint64_t remainingBytes = snapshot.totalWanted > snapshot.totalWantedDone
            ? snapshot.totalWanted - snapshot.totalWantedDone
            : 0;
        if (remainingBytes == 0) {
            snapshot.timeRemaining = 0;
        } else if (snapshot.downloadRate > 0) {
            snapshot.timeRemaining = (NSTimeInterval)remainingBytes / (double)snapshot.downloadRate;
        } else {
            snapshot.timeRemaining = -1; // Unknown / stalled
        }

        snapshot.pieces = [self piecesFromStatus:stat];
        snapshot.files = [self filesFromStatus:stat];
        snapshot.trackers = [self trackers];
        snapshot.magnetLink = [self magnetLink];
        snapshot.torrentFilePath = [self torrentFilePathFromStatus:stat];
        snapshot.downloadPath = [self downloadPathFromStatus:stat];
        snapshot.storageUUID = [self storageUUID];
        snapshot.isStorageMissing = [self isStorageMissing];

        snapshot.pieceLength = 0;
        snapshot.numberOfPieces = 0;
        auto ti = _torrentHandle.torrent_file();
        if (ti != nullptr) {
            snapshot.pieceLength = ti->piece_length();
            snapshot.numberOfPieces = ti->num_pieces();
        }

        self.snapshot = snapshot;
    } catch(...) {}
}

@end
