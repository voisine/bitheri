//
//  BTTxBuilder.h
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
//  limitations under the License.#import <Foundation/Foundation.h>


@class BTTx;

@interface BTTxBuilder : NSObject
+ (instancetype)instance;
- (BTTx *)buildTxForAddress:(NSString *)address andAmount:(NSArray *)amounts
                 andAddress:(NSArray *)addresses andError:(NSError **)error;
@end

@protocol BTTxBuilderProtocol

@required
- (BTTx *)buildTxForAddress:(NSString *)address WithUnspendTxs:(NSArray *)unspendTxs andTx:(BTTx *)tx;
@end

@interface BTTxBuilderEmptyWallet : NSObject <BTTxBuilderProtocol>
@end

@interface BTTxBuilderWithoutFee : NSObject <BTTxBuilderProtocol>
@end

@interface BTTxBuilderWithoutCharge : NSObject <BTTxBuilderProtocol>
@end

@interface BTTxBuilderDefault : NSObject <BTTxBuilderProtocol>
@end