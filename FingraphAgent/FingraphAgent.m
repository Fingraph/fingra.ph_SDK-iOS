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
#import "FingraphAgent.h"
#import "DBHandler.h"

#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <net/if.h>
#include <net/if_dl.h>

#include <sys/types.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <string.h>

#include <CommonCrypto/CommonDigest.h>

#define DEFAULT_CONTINUE_SESSION 10
#define FINGRAPH_TIMEOUT 3

#define FIN_APP_KEY @"FinAppKey"
#define FIN_SESSION_ID @"FinSessionID"
#define FIN_PAUSE_TIME @"FinPauseTime"

#if ! defined(IFT_ETHER)
#define IFT_ETHER 0x6/* Ethernet CSMACD */
#endif


@interface NSString (trim)
- (NSString *)ltrim;
- (NSString *)rtrim;
- (NSString *)trim;
@end

@implementation NSString (Trim)

- (NSString *)ltrim{
	NSCharacterSet *cs = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSUInteger len = [self length];
	int i;
	for(i=0; i < len; i++) {
		unichar c = [self characterAtIndex:i];
		if ( [cs characterIsMember:c] == NO ) break;
	}
	
	NSString *trimmed = [self substringFromIndex:i];
	
	return trimmed;
}


- (NSString *)rtrim {
	NSCharacterSet *cs = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSUInteger len = [self length];
	int i;
	for (i=(len-1); i >= 0; i--) {
		unichar c = [self characterAtIndex:i];
		if ( [cs characterIsMember:c] == NO ) break;
	}
	
	NSString *trimmed = [self substringToIndex:i+1];
	
	return trimmed;
}


- (NSString *)trim {
	NSCharacterSet *cs = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSUInteger len = [self length];
	int start, end;
	unichar c;
	
	for (start=0; start < len; start++) {
		c = [self characterAtIndex:start];
		if ( [cs characterIsMember:c] == NO ) break;
	}
	
	for (end=(len-1); end >= start; end--) {
		c = [self characterAtIndex:end];
		if ( [cs characterIsMember:c] == NO ) break;
	}
	
	NSRange r = NSMakeRange(start, end-start+1);
	NSString *trimmed = [self substringWithRange:r];
	
	return trimmed;
}

@end

@interface FingraphAgent (){
    NSString *serverURL;
    
    NSUserDefaults *defaults;
    
    DBHandler *dbHandler;
    NSOperationQueue *requestQueue;
}

@end

@implementation FingraphAgent

@synthesize sessionID;
@synthesize appkey;
@synthesize userId;
@synthesize continueSession;


static FingraphAgent *__sharedFingraphAgent;

+ (FingraphAgent *)sharedFingraphAgent {
    if(__sharedFingraphAgent == nil) {
        @synchronized(self){
            if(__sharedFingraphAgent == nil){
                __sharedFingraphAgent = [[FingraphAgent alloc] init];
            }
        }
    }
    return __sharedFingraphAgent;
}

+ (void)releaseSharedFingraphAgent {
    [[NSNotificationCenter defaultCenter] removeObserver:__sharedFingraphAgent name:UIApplicationWillResignActiveNotification object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver:__sharedFingraphAgent name:UIApplicationWillEnterForegroundNotification object: nil];
    [__sharedFingraphAgent release];
    __sharedFingraphAgent = nil;
}

-(id)init {
    if(self = [super init]) {
        userId = @"";
        continueSession = DEFAULT_CONTINUE_SESSION;
        sessionID = nil;
        serverURL = FINGRAPHAGENT_SERVER_URL;
        defaults = [NSUserDefaults standardUserDefaults];
        
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(endSession)
                                                     name:UIApplicationWillResignActiveNotification object: nil];
        
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(startSession)
                                                     name:UIApplicationWillEnterForegroundNotification object: nil];
        dbHandler = [DBHandler sharedDBHandler];
        requestQueue = [[NSOperationQueue alloc]init];
    }
    
    return self;
}

- (void)dealloc {
    [sessionID release];
    [appkey release];
    [userId release];
    [defaults release];
    [serverURL release];
    
    [super dealloc];
}

+ (void )onStartSession:(NSString *)appkey {
    FingraphAgent *fingraphAgent = [FingraphAgent sharedFingraphAgent];
    [fingraphAgent setAppkey:appkey];
    [fingraphAgent startSession];
}

+ (void)onEvent:(NSString *)eventKey {
    FingraphAgent *fingraphAgent = [FingraphAgent sharedFingraphAgent];
    [fingraphAgent event:eventKey];
}

+ (void)onEndSession {
    FingraphAgent *fingraphAgent = [FingraphAgent sharedFingraphAgent];
    [fingraphAgent endSession];
}

+ (void)onPageView {
    FingraphAgent *fingraphAgent = [FingraphAgent sharedFingraphAgent];
    [fingraphAgent pageView];
}

+ (void)setUserId:(NSString *)userId{
    FingraphAgent *fingraphAgent = [FingraphAgent sharedFingraphAgent];
    [fingraphAgent setUserId:userId];
}

+ (void)setContinueSession:(long)continueSession {
    FingraphAgent *fingraphAgent = [FingraphAgent sharedFingraphAgent];
    [fingraphAgent setContinueSession:continueSession];
}


- (BOOL)startSession {
    NSString *prevSession = [defaults objectForKey:FIN_SESSION_ID];
    NSDate *pauseTime = [defaults objectForKey:FIN_PAUSE_TIME];
    NSString *defaultAppkey = [defaults objectForKey:FIN_APP_KEY];
    
    if(appkey == nil){
        if(defaultAppkey != nil){
            appkey = defaultAppkey;
        }
        else {
            return false;
        }
    }
    else {
        if ([appkey isEqualToString:@""]) return false;
        [defaults setObject:appkey forKey:FIN_APP_KEY];
        [defaults synchronize];
    }
    
    if (prevSession == nil || pauseTime == nil || [[NSDate date] timeIntervalSinceDate:pauseTime]>continueSession){
        NSString *newSession = [self uuid];
        [self setSessionID:newSession];
        
        [defaults setObject:newSession forKey:FIN_SESSION_ID];
        [defaults synchronize];
        
        [self sendLogWithCommand:@"STARTSESS" andValue:nil];
    }
    else {
        [self setSessionID:prevSession];
    }
    return true;
}

- (void)pageView {
    [self sendLogWithCommand:@"PAGEVIEW" andValue:nil];
}

- (void )event:(NSString *)eventKey {
    [self sendLogWithCommand:@"EVENT" andValue:@{@"eventkey":eventKey}];
}

- (void)endSession {
    NSDate *pauseTime = [NSDate date];
    [defaults setObject:pauseTime forKey:FIN_PAUSE_TIME];
    [defaults synchronize];
    [self sendLogWithCommand:@"ENDSESS" andValue:nil];
}

- (void)sendLogWithCommand:(NSString *)command andValue:(NSDictionary *)value{
    if (sessionID == nil){
        BOOL success=[self startSession];
        if (!success){
            // FAIL : Don't have appkey
            NSLog(@"[FingraphAgent] Fingraph Appkey is not correct");
            return;
        }
    }
    // Make Log String
    NSDictionary *params = [self makeLogDictionaryWithCommand:command andValue:value];
    if ([NSJSONSerialization isValidJSONObject:params]){
        NSData *data = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
        NSString *tmp =[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *paramsString = [[tmp stringByReplacingOccurrencesOfString:@"\n" withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""];
        [self sendLog:paramsString];
        [paramsString release];
    }
    else {
        NSLog(@"[FingraphAgent] Log String is not valid");
    }
}


- (NSDictionary *)makeLogDictionaryWithCommand:(NSString *)command andValue:(NSDictionary *)valueDict{
    NSString *udid = @"";
    NSString *localTime = @"";
    NSString *standardTime = @"";
    NSString *language = @"";
    NSString *country = @"";
    NSString *appVersion = @"";
    NSString *osVersion = @"";
    NSString *resolution = @"";
    
    udid = [self identifier];
    NSLocale *currentLocale = [NSLocale currentLocale];
    
    language = [currentLocale objectForKey:NSLocaleLanguageCode];
    country = [currentLocale objectForKey:NSLocaleCountryCode];
    
    language = [language lowercaseString];
    country = [country uppercaseString];
    
    NSDate *date = [[NSDate alloc] init];
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit fromDate:date];
    
    localTime = [NSString stringWithFormat:@"%04d%02d%02d%02d%02d%02d", components.year, components.month, components.day, components.hour, components.minute, components.second];
    
    
    NSInteger millisecondsFromGMT = [[NSTimeZone localTimeZone] secondsFromGMT];
    
    components = [[NSCalendar currentCalendar] components:NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit |
                  NSSecondCalendarUnit fromDate:[NSDate dateWithTimeInterval:-millisecondsFromGMT sinceDate:date]];
    
    standardTime = [NSString stringWithFormat:@"%04d%02d%02d%02d%02d%02d", components.year, components.month, components.day, components.hour, components.minute, components.second];
    
    [date release];
    
    appVersion = [self getAppVersion];
    osVersion = [self getOSVersion];
    
    CGSize screenSize = [[[UIScreen mainScreen] currentMode] size];
    
    if(screenSize.width<screenSize.height) {
        resolution = [NSString stringWithFormat:@"%dX%d", (int)screenSize.width, (int)screenSize.height];
    } else {
        resolution = [NSString stringWithFormat:@"%dX%d", (int)screenSize.height, (int)screenSize.width];
    }
    
    if (resolution == nil) resolution = @"";
    if (appVersion == nil) appVersion = @"";
    if (language == nil) language = @"";
    if (country == nil) country = @"";
    
    // get Device
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *device = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *params = [[[NSMutableDictionary alloc]
                                   initWithObjects:@[command,sessionID,standardTime,localTime,udid,device,osVersion,resolution,appVersion,language,country,appkey,@"",userId]
                                   forKeys:@[@"cmd",@"session",@"utctime",@"localtime",@"token",@"device",@"osversion",@"resolution",@"appversion",@"language",@"country",@"appkey",@"referrerkey",@"userid"]] autorelease];
    

    if (valueDict){
        for (id<NSCopying> key in [valueDict allKeys]){
            [params setObject:[valueDict objectForKey:key] forKey:key];
        }
    }
    return params;
}

-(void)sendLog:(NSString *)log{
    __block UIBackgroundTaskIdentifier bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication]endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        
        // Send Log
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverURL] cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:FINGRAPH_TIMEOUT];
        [request addValue:@"application/json" forHTTPHeaderField:@"Content-type"];
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody:[log dataUsingEncoding:NSUTF8StringEncoding]];
        [NSURLConnection sendAsynchronousRequest:request queue:requestQueue completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
            if ([(NSHTTPURLResponse *)response statusCode] == 200){
                // Success
                [self sendFailedDBLogs];
            }
            else {
                // Failed
                NSLog(@"[FingraphAgent]Failed to send log");
                NSLog(@"[FingraphAgent]Response statusCode : %d",[(NSHTTPURLResponse *)response statusCode]);
                [dbHandler insertLog:log];
            }
        }];
    });
}

- (void)sendFailedDBLogs{
    NSMutableArray *logs = [[NSMutableArray alloc]init];
    NSString *lastLog = nil;
    for (int i=0;i<100;i++){
        lastLog = [[dbHandler selectFailedLog] objectForKey:@"log"];
        if (lastLog == nil || lastLog == NULL) break;
        [logs addObject:[NSJSONSerialization JSONObjectWithData:[lastLog dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]];
    }
    if ([logs count] ==0){
        [logs release];
        return;
    }
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    
    NSError *error = nil;
    NSData *log = [NSJSONSerialization dataWithJSONObject:logs options:0 error:&error];
    if (error != nil){
        NSLog(@"%@",[error description]);
        [logs release];
        return;
    }
    
    // Send Log
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverURL] cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:FINGRAPH_TIMEOUT];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:log];
    [NSURLConnection sendAsynchronousRequest:request queue:requestQueue completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if ([(NSHTTPURLResponse *)response statusCode] == 200){
            // Success
            [self sendFailedDBLogs];
        }
        else {
            // Failed
            NSLog(@"[FingraphAgent]Failed to send log");
            NSLog(@"[FingraphAgent]Response statusCode : %d",[(NSHTTPURLResponse *)response statusCode]);
            for (NSString *log in logs){
                [dbHandler insertLog:log];
            }
        }
    }];
}

- (NSString *)identifier{
    NSString *udid = @"";
    if([[[UIDevice currentDevice] systemVersion] floatValue] < 7.0){ // Under iOS7
        udid = [self getMacAddress];
        udid = [[self md5:udid] lowercaseString];
    } else { // After iOS7. Cannot use other values for identify device.
        udid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        udid = [self md5:udid];
    }
    return udid;
}

- (NSString *)uuid {
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef uuidStringRef = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    NSString *uuid = [NSString stringWithString:(NSString *)uuidStringRef];
    CFRelease(uuidStringRef);
    return uuid;
}

- (NSString *)getMacAddress {
    
    int                 mgmtInfoBase[6];
    char                *msgBuffer = NULL;
    size_t              length;
    unsigned char       macAddress[6];
    struct if_msghdr    *interfaceMsgStruct;
    struct sockaddr_dl  *socketStruct;
    NSString            *errorFlag = NULL;
    
    // Setup the management Information Base (mib)
    mgmtInfoBase[0] = CTL_NET;        // Request network subsystem
    mgmtInfoBase[1] = AF_ROUTE;       // Routing table info
    mgmtInfoBase[2] = 0;              
    mgmtInfoBase[3] = AF_LINK;        // Request link layer information
    mgmtInfoBase[4] = NET_RT_IFLIST;  // Request all configured interfaces
    
    // With all configured interfaces requested, get handle index
    if ((mgmtInfoBase[5] = if_nametoindex("en0")) == 0) {
        errorFlag = @"if_nametoindex failure";
    } else {
        // Get the size of the data available (store in len)
        if (sysctl(mgmtInfoBase, 6, NULL, &length, NULL, 0) < 0) {
            errorFlag = @"sysctl mgmtInfoBase failure";
        } else {
            // Alloc memory based on above call
            if ((msgBuffer = malloc(length)) == NULL) {
                errorFlag = @"buffer allocation failure";
            } else {
                // Get system information, store in buffer
                if (sysctl(mgmtInfoBase, 6, msgBuffer, &length, NULL, 0) < 0) {
                    errorFlag = @"sysctl msgBuffer failure";
                }
            }
        }
    }
    
    // Befor going any further...
    if (errorFlag != NULL) {
        free(msgBuffer);
        return errorFlag;
    }
    
    // Map msgbuffer to interface message structure
    interfaceMsgStruct = (struct if_msghdr *) msgBuffer;
    
    // Map to link-level socket structure
    socketStruct = (struct sockaddr_dl *) (interfaceMsgStruct + 1);
    
    // Copy link layer address data in socket structure to an array
    
    memcpy(&macAddress, socketStruct->sdl_data + socketStruct->sdl_nlen, 6);
    
    // Read from char array into a string object, into traditional Mac address format
    NSString *macAddressString = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", 
                                  macAddress[0], macAddress[1], macAddress[2], 
                                  macAddress[3], macAddress[4], macAddress[5]];
    
    // Release the buffer memory
    free(msgBuffer);
    
    return macAddressString;
}

- (BOOL) localWiFiAvailable {
    struct ifaddrs *addresses;
    struct ifaddrs *cursor;
    BOOL wiFiAvailable = NO;
    if (getifaddrs(&addresses) != 0) return NO;
    
    cursor = addresses;
    while (cursor != NULL) {
        if (cursor -> ifa_addr -> sa_family == AF_INET
            && !(cursor -> ifa_flags & IFF_LOOPBACK)) // Ignore the loopback address
        {
            // Check for WiFi adapter
            if (strcmp(cursor -> ifa_name, "en0") == 0) {
                wiFiAvailable = YES;
                break;
            }
        }
        cursor = cursor -> ifa_next;
    }
    
    freeifaddrs(addresses);
    return wiFiAvailable;
}


-(NSString*) md5:(NSString*)srcStr {
	const char *cStr = [srcStr UTF8String];
	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(cStr, strlen(cStr), result);
	return [NSString stringWithFormat:
			@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
			result[0],result[1],result[2],result[3],result[4],result[5],result[6],result[7],
			result[8],result[9],result[10],result[11],result[12],result[13],result[14],result[15]];
}

- (NSString *)getCurDateString:(NSString *)outformat {
    return [self getCurDateString:outformat timeZoneWithName:@"Asia/Seoul"];
}

- (NSString *)getCurDateString:(NSString *)outformat timeZoneWithName:(NSString *)timeZoneWithName {
    NSTimeZone *krTimeZone = [NSTimeZone timeZoneWithName:timeZoneWithName];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    NSString *dateString;
    
    [dateFormat setTimeZone:krTimeZone];
    [dateFormat setDateFormat:outformat];
    
    NSDate *date = [[NSDate alloc] init];
    
    dateString = [dateFormat stringFromDate:date];
    [date release];
    [dateFormat release];
    
    return dateString;
}

- (NSString *)getAppVersion {
    NSDictionary *infoDic = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = [infoDic objectForKey:@"CFBundleShortVersionString"];
    
    if([appVersion length] > 100) {
        appVersion = [appVersion substringToIndex:100];
    }
    
    return appVersion;
    
}

- (NSString *)getOSVersion {
    NSString *osVersion = [[UIDevice currentDevice] systemVersion];
    
    if([osVersion length] > 100) {
        osVersion = [osVersion substringToIndex:100];
    }
    
    return osVersion;
}

#pragma mark - Methods for Unit Test
-(void)setServerURL:(NSString *)_serverURL{
    serverURL=_serverURL;
}
@end