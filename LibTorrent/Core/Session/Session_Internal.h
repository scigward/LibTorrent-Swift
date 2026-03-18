//
//  Session_Internal.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>
#include <unordered_map>

#import "Session.h"
#import "SessionSettings_Internal.h"

#import "libtorrent/session.hpp"
#import "libtorrent/torrent_handle.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface Session ()
@property lt::session *session;
@property (strong, nonatomic) dispatch_queue_t filesQueue;
@property (strong, nonatomic) NSThread *eventsThread;
@property (strong, nonatomic) NSHashTable *delegates;
@property (strong, nonatomic) NSMutableDictionary<TorrentHashes*, TorrentHandle*> *torrentsMap;
@property (strong, nonatomic, nullable) NSString *lastExternalIP;

- (std::unordered_map<lt::sha1_hash, std::unordered_map<std::string, std::unordered_map<lt::tcp::endpoint, std::unordered_map<int, int>>>>) updatedTrackerStatuses;
- (TorrentHandle *)torrentForHandle:(lt::torrent_handle)th;
- (void)notifyDelegatesWithPieceFinished:(lt::piece_index_t)pieceIndex forHandle:(lt::torrent_handle)th;
- (void)notifyDelegatesWithPieceData:(NSData *)data atIndex:(lt::piece_index_t)pieceIndex forHandle:(lt::torrent_handle)th;
@end

NS_ASSUME_NONNULL_END
