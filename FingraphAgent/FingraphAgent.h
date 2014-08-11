/*******************************************************************************
 * Copyright 2014 tgrape Inc.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define FINGRAPHAGENT_SERVER_URL @"http://localhost:8080/sdk/iphone?q="

@interface FingraphAgent : NSObject  {

    NSString *sessionID;
    NSString *appkey;
    NSString *userId;
    long continueSession;
}

@property (retain, nonatomic) NSString *sessionID;
@property (retain, nonatomic) NSString *appkey;
@property (retain, nonatomic) NSString *userId;
@property long continueSession;

+ (FingraphAgent *)sharedFingraphAgent;
+ (void)releaseSharedFingraphAgent;

+ (void)onStartSession:(NSString *)apiKey;
+ (void)onEvent:(NSString *)eventKey;
+ (void)onEndSession;
+ (void)onPageView;

+ (void)setUserId:(NSString *)userId;
+ (void)setContinueSession:(long)continueSession;

@end
