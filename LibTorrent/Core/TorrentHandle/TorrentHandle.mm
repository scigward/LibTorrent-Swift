//
//  NSObject+TorrentHandle.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "TorrentHandle_Internal.h"
#import "FileEntry_Internal.h"
#import "TorrentTracker_Internal.h"
#import "Session_Internal.h"
#import "PeerInfo_Internal.h"

#import "NSData+Hex.h"

#import "libtorrent/torrent_status.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/magnet_uri.hpp"
#import "libtorrent/peer_info.hpp"

static std::vector<lt::download_priority_t> piecePrioritiesForFiles(
    lt::torrent_info const &torrentInfo,
    std::vector<lt::download_priority_t> const &filePriorities,
    bool firstLastPiecePriorityEnabled)
{
    auto const &files = torrentInfo.files();
    auto piecePriorities = std::vector<lt::download_priority_t>(torrentInfo.num_pieces(), lt::dont_download);

    for (int index = 0; index < files.num_files(); ++index) {
        auto fileIndex = static_cast<lt::file_index_t>(index);
        auto filePriority = filePriorities[index];
        if (filePriority <= lt::dont_download) {
            continue;
        }

        auto fileSize = files.file_size(fileIndex);
        if (fileSize <= 0) {
            continue;
        }

        auto const firstPiece = files.map_file(fileIndex, 0, 0).piece;
        auto const lastPiece = files.map_file(fileIndex, fileSize - 1, 1).piece;
        auto const pieceCount = static_cast<int>(lastPiece - firstPiece) + 1;
        auto const piecePriority = firstLastPiecePriorityEnabled ? lt::top_priority : filePriority;
        std::int64_t const edgeSpan = std::int64_t(torrentInfo.piece_length()) * 100;
        int edgePieceCount = static_cast<int>((fileSize + edgeSpan - 1) / edgeSpan);
        if (edgePieceCount > pieceCount) {
            edgePieceCount = pieceCount;
        }

        for (int pieceOffset = 0; pieceOffset < edgePieceCount; ++pieceOffset) {
            piecePriorities[static_cast<int>(firstPiece) + pieceOffset] = piecePriority;
            piecePriorities[static_cast<int>(lastPiece) - pieceOffset] = piecePriority;
        }

        for (int pieceIndex = static_cast<int>(firstPiece) + edgePieceCount;
             pieceIndex <= static_cast<int>(lastPiece) - edgePieceCount;
             ++pieceIndex) {
            piecePriorities[pieceIndex] = filePriority;
        }
    }

    return piecePriorities;
}

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
        _isFirstLastPiecePriority = NO;
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

    return 0;
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

    // Invalidate all caches since the underlying handle has been replaced
    _snapshot = nil;
    _cachedMagnetLink = nil;
    _cachedTorrentFilePath = nil;
    _lastSnapshotTotalDone = 0;
    _lastSnapshotHasMetadata = NO;
    _filesCacheDirty = YES;

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

- (void)applyPriorityConfiguration {
    if (!_torrentHandle.is_valid()) return;

    auto filePriorities = _torrentHandle.get_file_priorities();
    [self applyPriorityConfigurationWithFilePriorities:filePriorities saveResumeData:YES];
}

- (void)applyPriorityConfigurationWithFilePriorities:(const std::vector<lt::download_priority_t> &)filePriorities
                                      saveResumeData:(BOOL)saveResumeData {
    if (!_torrentHandle.is_valid()) return;

    // File priorities remain the source of truth. Piece priorities are derived from them
    // and the first/last-piece flag whenever any priority-related setting changes.
    _torrentHandle.prioritize_files(filePriorities);

    auto torrentInfoPtr = _torrentHandle.torrent_file();
    if (torrentInfoPtr != nullptr) {
        auto piecePriorities = piecePrioritiesForFiles(*torrentInfoPtr, filePriorities, _isFirstLastPiecePriority);
        _torrentHandle.prioritize_pieces(piecePriorities);
    }

    if (saveResumeData) {
        _torrentHandle.save_resume_data();
    }
}

- (void)setFirstLastPriorityDownload:(BOOL)enabled {
    _isFirstLastPiecePriority = enabled;
    [self applyPriorityConfiguration];
}

- (void)setPiecePriority:(NSInteger)pieceIndex priority:(uint8_t)priority {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    auto prio = static_cast<lt::download_priority_t>(priority);
    _torrentHandle.piece_priority(idx, prio);
}

- (void)setPieceDeadline:(NSInteger)pieceIndex deadline:(int)deadline {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    _torrentHandle.set_piece_deadline(idx, deadline);
}

- (void)resetPieceDeadline:(NSInteger)pieceIndex {
    auto idx = static_cast<lt::piece_index_t>(static_cast<int>(pieceIndex));
    _torrentHandle.reset_piece_deadline(idx);
}

- (void)clearPieceDeadlines {
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
        double fileProgress = (size > 0) ? ((double)progresses[index] / (double)size) : 0.0;
        fileEntry.progress = (fileProgress > 1.0) ? 1.0 : fileProgress;
        fileEntry.priority = (FilePriority) priority;

        const auto fileSize = files.file_size(i);// > 0 ? files.file_size(i) : 0;
        const auto fileOffset = files.file_offset(i);

        const long long beginIdx = (fileOffset / pieceLength);
        const long long endIdx = fileSize > 0 ? ((fileOffset + fileSize - 1) / pieceLength) + 1 : beginIdx;

        fileEntry.begin_idx = beginIdx;
        fileEntry.end_idx = endIdx;
        fileEntry.num_pieces = (int)(endIdx - beginIdx);
        auto array = [[NSMutableArray<NSNumber *> alloc] init];
        for (int j = 0; j < fileEntry.num_pieces; j++) {
            auto index = static_cast<lt::piece_index_t>(j + (int)beginIdx);
            [array addObject: [NSNumber numberWithBool: stat.pieces.get_bit(index)]];
        }
        fileEntry.pieces = array;

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
    auto priorities = _torrentHandle.get_file_priorities();
    priorities[(int)fileIndex] = static_cast<lt::download_priority_t>(priority);
    [self applyPriorityConfigurationWithFilePriorities:priorities saveResumeData:YES];
    _filesCacheDirty = YES;
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    auto priorities = _torrentHandle.get_file_priorities();
    for (int i = 0; i < fileIndexes.count; i++) {
        int index = (int)fileIndexes[i].integerValue;
        priorities[index] = static_cast<lt::download_priority_t>(priority);
    }
    [self applyPriorityConfigurationWithFilePriorities:priorities saveResumeData:YES];
    _filesCacheDirty = YES;
}

- (void)setAllFilesPriority:(FilePriority)priority {
    std::vector<lt::download_priority_t> array;
    for (int i = 0; i < _torrentHandle.torrent_file().get()->files().num_files(); i++) {
        array.push_back(static_cast<lt::download_priority_t>(priority));
    }
    [self applyPriorityConfigurationWithFilePriorities:array saveResumeData:YES];
    _filesCacheDirty = YES;
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

- (NSArray<PeerInfo *> *)peerInfo {
    if (!_torrentHandle.is_valid()) return @[];

    std::vector<lt::peer_info> peers;
    try {
        _torrentHandle.get_peer_info(peers);
    } catch(...) {
        return @[];
    }

    NSMutableArray<PeerInfo *> *results = [[NSMutableArray alloc] initWithCapacity:peers.size()];

    for (const auto &peer : peers) {
        PeerInfo *info = [[PeerInfo alloc] init];

        // IP address with port
        auto ep = peer.ip;
        std::string addr = ep.address().to_string() + ":" + std::to_string(ep.port());
        info.ip = [NSString stringWithUTF8String:addr.c_str()];

        info.isSeeder = bool(peer.flags & lt::peer_info::seed);

        // Client identification (guard against non-UTF8 client strings from malicious peers)
        NSString *clientName = [NSString stringWithUTF8String:peer.client.c_str()];
        info.client = clientName ?: @"Unknown";

        // Peer progress
        info.progress = peer.progress;

        // Transfer stats
        info.totalDownload = peer.total_download;
        info.totalUpload = peer.total_upload;
        info.downloadSpeed = peer.down_speed;
        info.uploadSpeed = peer.up_speed;

        // Connection flags (matching hayase: incoming, outgoing, utp, encrypted)
        NSMutableArray<NSString *> *flags = [[NSMutableArray alloc] init];

        if (peer.flags & lt::peer_info::utp_socket) {
            [flags addObject:@"utp"];
        }

        if (peer.flags & lt::peer_info::local_connection) {
            [flags addObject:@"outgoing"];
        } else {
            [flags addObject:@"incoming"];
        }

        if (peer.flags & lt::peer_info::rc4_encrypted) {
            [flags addObject:@"encrypted"];
        }

        info.connectionFlags = [flags copy];

        [results addObject:info];
    }

    return [results copy];
}

// MARK: - Streaming Methods

- (void)prepareForStreaming:(NSInteger)fileIndex {
    if (!_torrentHandle.is_valid()) return;

    auto ti = _torrentHandle.torrent_file();
    if (ti == nullptr) return;

    auto info = ti.get();
    auto files = info->files();
    if (fileIndex < 0 || fileIndex >= files.num_files()) return;

    auto i = static_cast<lt::file_index_t>((int)fileIndex);
    const int pieceLength = info->piece_length();
    const auto fileOffset = files.file_offset(i);
    const auto fileSize = files.file_size(i);

    if (fileSize == 0 || pieceLength == 0) return;

    const int firstPiece = (int)(fileOffset / pieceLength);
    const int lastPiece = (int)((fileOffset + fileSize - 1) / pieceLength);
    const int totalFilePieces = lastPiece - firstPiece + 1;

    // Enable sequential download for the torrent
    _torrentHandle.set_flags(lt::torrent_flags::sequential_download);

    // Set the target file to top priority
    _torrentHandle.file_priority(i, lt::download_priority_t{7}); // top priority

    // Set all other files to don't-download so we focus on the streaming file
    for (int f = 0; f < files.num_files(); f++) {
        if (f != fileIndex) {
            _torrentHandle.file_priority(static_cast<lt::file_index_t>(f), lt::download_priority_t{0});
        }
    }

    // Aggressively prioritize initial pieces for fast playback start
    // Use a "head window" of pieces with tight deadlines
    const int headWindow = std::min(totalFilePieces, std::max(16, (int)(2 * 1024 * 1024 / pieceLength))); // At least 2MB worth
    const int tailWindow = std::min(4, totalFilePieces); // Last few pieces for container metadata (mp4 moov atom etc)

    for (int p = firstPiece; p <= lastPiece; p++) {
        auto idx = static_cast<lt::piece_index_t>(p);
        int relPiece = p - firstPiece;

        if (relPiece < headWindow) {
            // Head pieces: highest priority with tight deadline
            _torrentHandle.piece_priority(idx, lt::download_priority_t{7});
            _torrentHandle.set_piece_deadline(idx, relPiece * 10); // 10ms between each piece deadline
        } else if (relPiece >= totalFilePieces - tailWindow) {
            // Tail pieces: high priority for container metadata
            _torrentHandle.piece_priority(idx, lt::download_priority_t{7});
            _torrentHandle.set_piece_deadline(idx, headWindow * 10 + (relPiece - (totalFilePieces - tailWindow)) * 10);
        } else {
            // Middle pieces: normal priority, sequential will handle order
            _torrentHandle.piece_priority(idx, lt::download_priority_t{4});
        }
    }

    _filesCacheDirty = YES;
    _torrentHandle.save_resume_data();
}

- (void)setStreamingPiecePriorities:(NSInteger)fileIndex offset:(uint64_t)byteOffset {
    if (!_torrentHandle.is_valid()) return;

    auto ti = _torrentHandle.torrent_file();
    if (ti == nullptr) return;

    auto info = ti.get();
    auto files = info->files();
    if (fileIndex < 0 || fileIndex >= files.num_files()) return;

    auto i = static_cast<lt::file_index_t>((int)fileIndex);
    const int pieceLength = info->piece_length();
    const auto fileOffset = files.file_offset(i);
    const auto fileSize = files.file_size(i);

    if (fileSize == 0 || pieceLength == 0) return;

    const int firstPiece = (int)(fileOffset / pieceLength);
    const int lastPiece = (int)((fileOffset + fileSize - 1) / pieceLength);

    // Calculate the piece corresponding to the current byte offset within the file
    const int currentPiece = (int)((fileOffset + byteOffset) / pieceLength);

    if (currentPiece < firstPiece || currentPiece > lastPiece) return;

    // Sliding window: prioritize pieces ahead of the playback position
    // Window size: enough for ~5 seconds of buffering at typical video bitrates
    const int windowSize = std::min(lastPiece - currentPiece + 1, std::max(32, (int)(8 * 1024 * 1024 / pieceLength))); // At least 8MB ahead

    // Also keep tail pieces prioritized for container metadata
    const int tailWindow = std::min(4, lastPiece - firstPiece + 1);

    for (int p = firstPiece; p <= lastPiece; p++) {
        auto idx = static_cast<lt::piece_index_t>(p);
        int aheadOfCurrent = p - currentPiece;

        if (aheadOfCurrent >= 0 && aheadOfCurrent < windowSize) {
            // Pieces in the streaming window: highest priority with tight deadlines
            _torrentHandle.piece_priority(idx, lt::download_priority_t{7});
            _torrentHandle.set_piece_deadline(idx, aheadOfCurrent * 20); // 20ms increments
        } else if (p > lastPiece - tailWindow) {
            // Keep tail pieces at high priority
            _torrentHandle.piece_priority(idx, lt::download_priority_t{6});
        } else if (p < currentPiece) {
            // Already-played pieces: low priority
            _torrentHandle.piece_priority(idx, lt::download_priority_t{1});
        } else {
            // Far-ahead pieces: normal priority
            _torrentHandle.piece_priority(idx, lt::download_priority_t{4});
        }
    }
}

- (void)clearStreamingPriorities {
    if (!_torrentHandle.is_valid()) return;

    auto ti = _torrentHandle.torrent_file();
    if (ti == nullptr) return;

    auto info = ti.get();
    const int numPieces = info->num_pieces();

    // Reset all piece priorities to default
    for (int p = 0; p < numPieces; p++) {
        auto idx = static_cast<lt::piece_index_t>(p);
        _torrentHandle.piece_priority(idx, lt::download_priority_t{4});
        _torrentHandle.reset_piece_deadline(idx);
    }

    // Disable sequential download
    _torrentHandle.unset_flags(lt::torrent_flags::sequential_download);

    // Reset all file priorities to default
    for (int f = 0; f < info->files().num_files(); f++) {
        _torrentHandle.file_priority(static_cast<lt::file_index_t>(f), lt::download_priority_t{4});
    }

    _filesCacheDirty = YES;
    _torrentHandle.save_resume_data();
}

- (void)updateSnapshot {
    if (!self.isValid) return;

    auto snapshot = [[TorrentHandleSnapshot alloc] init];
    try {
        auto stat = _torrentHandle.status();

        BOOL hasMetadata = [self hasMetadataFromStatus:stat];
        uint64_t totalDone = [self totalDoneFromStatus:stat];
        BOOL metadataChanged = (hasMetadata != _lastSnapshotHasMetadata);
        BOOL progressChanged = (totalDone != _lastSnapshotTotalDone);

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
        snapshot.hasMetadata = hasMetadata;
        snapshot.total = [self totalFromStatus:stat];
        snapshot.totalDone = totalDone;
        snapshot.totalWanted = [self totalWantedFromStatus:stat];
        snapshot.totalWantedDone = [self totalWantedDoneFromStatus:stat];
        snapshot.totalDownload = [self totalDownloadFromStatus:stat];
        snapshot.totalUpload = [self totalUploadFromStatus:stat];
        snapshot.isPaused = [self isPausedFromStatus:stat];
        snapshot.isFinished = [self isFinishedFromStatus:stat];
        snapshot.isSeed = [self isSeedFromStatus:stat];
        snapshot.isSequential = [self isSequentialFromStatus:stat];
        snapshot.isFirstLastPiecePriority = [self isFirstLastPiecePriority];

        // Only rebuild pieces and files when download progress or priorities change
        if (_snapshot == nil || progressChanged || metadataChanged || _filesCacheDirty) {
            snapshot.pieces = [self piecesFromStatus:stat];
            snapshot.files = [self filesFromStatus:stat];
            _filesCacheDirty = NO;
        } else {
            snapshot.pieces = _snapshot.pieces;
            snapshot.files = _snapshot.files;
        }

        snapshot.trackers = [self trackers];

        // Cache magnetLink: only regenerate when metadata availability changes
        if (metadataChanged || _cachedMagnetLink == nil) {
            _cachedMagnetLink = [self magnetLink];
        }
        snapshot.magnetLink = _cachedMagnetLink;

        // Cache torrentFilePath: only regenerate when metadata availability changes
        if (metadataChanged || _cachedTorrentFilePath == nil) {
            _cachedTorrentFilePath = [self torrentFilePathFromStatus:stat];
        }
        snapshot.torrentFilePath = _cachedTorrentFilePath;

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

        // Time remaining calculation (matching hayase's timeRemaining)
        if (stat.download_rate > 0 && stat.total_wanted > stat.total_wanted_done) {
            snapshot.timeRemaining = (NSInteger)(((double)(stat.total_wanted - stat.total_wanted_done)) / stat.download_rate);
        } else if (stat.total_wanted == stat.total_wanted_done) {
            snapshot.timeRemaining = 0;
        } else {
            snapshot.timeRemaining = -1; // unknown
        }

        // Total connected peers (matching hayase's wires / _peersLength)
        snapshot.numberOfConnectedPeers = stat.num_connections;

        // Protocol status flags (matching hayase's protocolStatus)
        auto settings = _session.session->get_settings();
        snapshot.isDhtRunning = settings.get_bool(lt::settings_pack::enable_dht);
        snapshot.isLsdRunning = settings.get_bool(lt::settings_pack::enable_lsd);
        snapshot.isPexEnabled = !(stat.flags & lt::torrent_flags::disable_pex);
        snapshot.hasIncomingConnections = (stat.num_peers > 0);

        _lastSnapshotTotalDone = totalDone;
        _lastSnapshotHasMetadata = hasMetadata;

        self.snapshot = snapshot;
    } catch(...) {}
}

@end
