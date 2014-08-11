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

#import "DBHandler.h"

@implementation DBHandler

+(DBHandler *)sharedDBHandler{
    static DBHandler *handler = nil;
    if (handler == nil){
        @synchronized(self){
            if (handler == nil){
                handler = [[DBHandler alloc]init];
            }
        }
    }
    return handler;
}

-(id)init{
    self = [super init];
    if (self != nil){
        // Build the path to the database file
        NSString *docsDir;
        NSArray *dirPaths;
        
        // Get the documents directory
        dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        docsDir = [dirPaths objectAtIndex:0];
        databasePath = [[NSString alloc] initWithString: [docsDir stringByAppendingPathComponent: @"fin.db"]];

        NSFileManager *filemgr = [[NSFileManager defaultManager] retain];
        
        semaphore = dispatch_semaphore_create(1);
        
        if ([filemgr fileExistsAtPath: databasePath ] == NO) {
            const char *dbpath = [databasePath UTF8String];
            
            if (sqlite3_open(dbpath, &finDB) == SQLITE_OK) {
                char *errMsg;
                const char *sql_stmt = "CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY AUTOINCREMENT, log TEXT)";
                
                if (sqlite3_exec(finDB, sql_stmt, NULL, NULL, &errMsg) != SQLITE_OK) {
                    NSLog(@"[FingraphAgent] Failed to create table");
                }
            }
            else {
                NSLog(@"Failed to open/create database");
            }
        }
        [filemgr release];
    }
    return self;
}

-(void)dealloc{
    [super dealloc];
    sqlite3_close(finDB);
}

-(sqlite3*)finDB{
    if (finDB){
        return finDB;
    }
    else if(sqlite3_open([databasePath UTF8String], &finDB)==SQLITE_OK){
        return finDB;
    }
    else {
        return nil;
    }
}

-(void)closeDB{
    if (finDB) {
        sqlite3_close(finDB);
        finDB = nil;
    };
}

-(void)insertLog:(NSString *)log{
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if ([self finDB]){
        const char *sql = [[NSString stringWithFormat:@"INSERT INTO logs (log) VALUES ('%@')",[log stringByReplacingOccurrencesOfString:@"'" withString:@"''"]] UTF8String];
        sqlite3_stmt *insertStmt = nil;
        if (sqlite3_prepare_v2(finDB, sql, -1, &insertStmt, nil) != SQLITE_OK){
            NSLog(@"[FingraphAgent]Failed to INSERT log");
        }
        if (sqlite3_step(insertStmt) != SQLITE_DONE){
            NSLog(@"[FingraphAgent]Failed to INSERT log");
        }
        sqlite3_finalize(insertStmt);
    }
    else {
        NSLog(@"[FingraphAgent]Cannot open DB");
    }
    dispatch_semaphore_signal(semaphore);
}

-(NSArray *)selectLogs{
    NSMutableArray *retval = [[[NSMutableArray alloc]init]autorelease];
    NSString *query = @"SELECT log,id FROM logs";
    sqlite3_stmt *statement;
    if ([self finDB]){
        if (sqlite3_prepare_v2(finDB, [query UTF8String], -1, &statement, nil) == SQLITE_OK){
            while(sqlite3_step(statement) == SQLITE_ROW){
                char* log = (char *)sqlite3_column_text(statement, 0);
                int rowId = sqlite3_column_int(statement, 1);
                NSDictionary *failedLog = [
                                           [NSDictionary alloc]
                                           initWithObjects:[NSArray arrayWithObjects:
                                                            [NSString stringWithCString:log encoding:NSUTF8StringEncoding],
                                                            [NSNumber numberWithInteger:rowId],
                                                            nil]
                                           forKeys:[NSArray arrayWithObjects:@"log",@"id", nil]];
                [retval addObject:failedLog];
            }
            sqlite3_finalize(statement);
        }
        else {
            NSLog(@"[FingraphAgent]Failed to select");
        }
    }
    else {
        NSLog(@"[FingraphAgent]Failed to open DB");
    }
    return retval;
}

-(NSDictionary *)selectFailedLog{
    dispatch_semaphore_wait(semaphore,DISPATCH_TIME_FOREVER);
    NSString *query = @"SELECT log,id FROM logs ORDER BY id LIMIT 1";
    sqlite3_stmt *statement;
    NSDictionary *lastLog = nil;
    int rowId = -1;
    if ([self finDB]){
        if (sqlite3_prepare_v2(finDB, [query UTF8String], -1, &statement, nil) == SQLITE_OK){
            while(sqlite3_step(statement) == SQLITE_ROW){
                char* log = (char *)sqlite3_column_text(statement, 0);
                rowId = sqlite3_column_int(statement, 1);
                NSString *logNSString = [NSString stringWithCString:log encoding:NSUTF8StringEncoding];
                if (logNSString == nil) lastLog = nil;
                else {
                    lastLog= [[[NSDictionary alloc]
                             initWithObjects:[NSArray arrayWithObjects:
                                              logNSString,
                                              [NSNumber numberWithInteger:rowId],
                                              nil]
                             forKeys:[NSArray arrayWithObjects:@"log",@"id", nil]]autorelease];
                }
            }
            sqlite3_finalize(statement);
            
            if (lastLog != nil && rowId != -1){
                const char *sql = [[NSString stringWithFormat:@"DELETE FROM logs WHERE id=%d",rowId] UTF8String];
                sqlite3_stmt *deleteStmt = nil;
                if (sqlite3_prepare_v2(finDB, sql, -1, &deleteStmt, nil) != SQLITE_OK){
                    NSLog(@"[FingraphAgent]Failed to DELETE logs");
                }
                if (SQLITE_DONE != sqlite3_step(deleteStmt)){
                    NSLog(@"[FingraphAgent]Failed to DELETE logs");
                }
                sqlite3_finalize(deleteStmt);
            }
        }
        else {
            NSLog(@"[FingraphAgent]Failed to select");
        }
    }
    else {
        NSLog(@"[FingraphAgent]Failed to open DB");
    }
    dispatch_semaphore_signal(semaphore);
    return lastLog;
}

#pragma mark - Private Methods
-(void)delete{
    dispatch_semaphore_wait(semaphore,DISPATCH_TIME_FOREVER);
    if ([self finDB]){
        const char *sql = [@"DELETE FROM logs" UTF8String];
        sqlite3_stmt *deleteStmt = nil;
        if (sqlite3_prepare_v2(finDB, sql, -1, &deleteStmt, nil) != SQLITE_OK){
            NSLog(@"[FingraphAgent]Failed to DELETE logs");
        }
        if (SQLITE_DONE != sqlite3_step(deleteStmt)){
             NSLog(@"[FingraphAgent]Failed to DELETE logs");
        }
        sqlite3_finalize(deleteStmt);
    }
    else {
        NSLog(@"[FingraphAgent]Cannot open DB");
    }
    dispatch_semaphore_signal(semaphore);
}
@end
