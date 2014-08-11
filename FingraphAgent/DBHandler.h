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
#import <sqlite3.h>
@interface DBHandler : NSObject{
    sqlite3 *finDB;
    @private
    NSString *databasePath;
    dispatch_semaphore_t semaphore;
}

+(DBHandler *)sharedDBHandler;
-(void)insertLog:(NSString *)log;
-(NSArray *)selectLogs;
-(NSDictionary *)selectFailedLog;
@end
