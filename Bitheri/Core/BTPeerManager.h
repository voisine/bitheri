//
//  BTPeerManager.h
//  bitheri
//
//  Copyright 2014 http://Bither.net
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <Foundation/Foundation.h>
#import "BTPeer.h"
#import "BTBlockChain.h"

@interface BTPeerManager : NSObject<BTPeerDelegate>

@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) uint32_t lastBlockHeight;
@property (nonatomic, readonly) double syncProgress;
@property (nonatomic, strong) BTBlockChain * blockChain;

@property (readonly) BOOL doneSyncFromSPV;

+ (instancetype)sharedInstance;

- (void)connect;
- (void)disconnect;
- (void)publishTransaction:(BTTx *)transaction completion:(void (^)(NSError *error))completion;

// transaction is considered verified when all peers have relayed it
- (BOOL)transactionIsVerified:(NSData *)txHash;

@property (nonatomic, strong) NSMutableSet *connectedPeers;

@end