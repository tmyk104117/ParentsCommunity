//
//  WCXMPPManager.m
//  WeChat
//
//  Created by Reese on 13-8-10.
//  Copyright (c) 2013年 Reese. All rights reserved.
//
// Log levels: off, error, warn, info, verbose

#import "WCXMPPManager.h"
#import "GCDAsyncSocket.h"
#import "XMPP.h"
#import "XMPPReconnect.h"
#import "XMPPCapabilities.h"

#import "XMPPRoster.h"
#import "XMPPMessage.h"
#import "TURNSocket.h"
#import "IUtil.h"
#import "SystemNotificationObject.h"
#import "NSString+XMLEntities.h"
#import "ASIHttpRequest/ASIFormDataRequest.h"


#import "GroupObject.h"

#define DOCUMENT_PATH NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0]
#define CACHES_PATH NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0]

@implementation WCXMPPManager





static WCXMPPManager *sharedManager;

+(WCXMPPManager*)sharedInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        sharedManager=[[WCXMPPManager alloc]init];
        [DDLog addLogger:[DDTTYLogger sharedInstance]];
        ;
        [[NSUserDefaults standardUserDefaults]setObject:[IUtil replaceAT:[WCUserObject getLoginUserId]] forKey:kXMPPmyJID];
        [[NSUserDefaults standardUserDefaults]setObject:[[NSUserDefaults standardUserDefaults]objectForKey:kMY_USER_PASSWORD] forKey:kXMPPmyPassword];
        BOOL success = [[NSUserDefaults standardUserDefaults]synchronize];
        DDLogVerbose(@"%hhd",success);
// Setup the XMPP stream
       [sharedManager setupStream];
        
        
        
        

        
    });
    
    [[NSNotificationCenter defaultCenter]addObserver:sharedManager selector:@selector(reachabilityChanged:) name:NetworkReachabilityChangedNotification object:nil];
    return sharedManager;
}

-(void)reachabilityChanged:(NSNotification *)note
{
	Reachability* curReach = [note object];
	NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
    if([curReach.key isEqualToString:@"InternetConnection"])
    {
        if(curReach.currentReachabilityStatus == kNotReachable)
        {
            NSLog(@"%@",@"不好意思断网了");
            [[NSNotificationCenter defaultCenter] postNotificationName:ConnectionNoReach object:nil];
            [[WCXMPPManager sharedInstance] teardownStream];
            [[WCXMPPManager sharedInstance] startReConnectTimer];

        }else{
            [[NSNotificationCenter defaultCenter] postNotificationName:ConnectionReach object:nil];
            [[WCXMPPManager sharedInstance] stopReConnectTimer];
        }
    }else{
    }
}

-(void)startReConnectTimer
{
    if(!reconnectTimer)
    {
        reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:[WCXMPPManager sharedInstance] selector:@selector(reconnect:) userInfo:nil repeats:YES];
    }
}


-(void)stopReConnectTimer
{
    if(reconnectTimer)
    {
        [reconnectTimer invalidate];
        reconnectTimer = nil;
    }
}

-(void)reconnect:(NSTimer*)theTimer {
    NSLog(@"重连计数器");
    [xmppStream disconnect];
    if([xmppStream isDisconnected])
    {
        [[WCXMPPManager sharedInstance] connect];
    }

}

- (void)dealloc
{
	[self teardownStream];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma  mark ------收发消息-------
//- (void)sendMessage:(XMPPMessage *)aMessage
//{
//    [xmppStream sendElement:aMessage];
//    NSString *body = [[aMessage elementForName:@"body"] stringValue];
//   // NSString *meesageStyle=[[aMessage attributeForName:@"type"] stringValue];
//    NSString *meesageTo = [[aMessage to]bare];
//    NSArray *strs=[meesageTo componentsSeparatedByString:@"@"];
//    
//    //创建message对象
//    WCMessageObject *msg=[[WCMessageObject alloc]init];
//    [msg setMessageDate:[NSDate date]];
//    [msg setMessageFrom:[[NSUserDefaults standardUserDefaults]objectForKey:kMY_USER_ID]];
//    
//    [msg setMessageTo:strs[0]];
//    //判断多媒体消息
//    
//    if ([[body substringToIndex:3]isEqualToString:@"[1]"]) {
//        
//    
//        [msg setMessageType:[NSNumber numberWithInt:kWCMessageTypeImage]];
//        body=[body substringFromIndex:3];
//    }else
//    [msg setMessageType:[NSNumber numberWithInt:kWCMessageTypePlain]];
//    
//    
//    [msg setMessageContent:body];
//    [WCMessageObject save:msg];
    //发送全局通知
//    [[NSNotificationCenter defaultCenter]postNotificationName:kXMPPNewMsgNotifaction object:msg ];
//    [msg release];
//}

-(void)sendMessage2Room:(NSString *)roomXMPPID message:(XMPPMessage *)message
{
    //创建message对象
    NSString *toName = [message toStr];
    WCMessageObject *msg=[WCMessageObject messageWithType:kWCMessageTypePlain];
    NSArray *strs=[toName componentsSeparatedByString:@"@"];
    NSDate *messagesDate = [NSDate date];
    long long interval = [[NSNumber numberWithDouble:[messagesDate timeIntervalSince1970]*1000]longLongValue];
    [msg setMessageDate:messagesDate];
    NSString *role = [WCUserObject getLoginAccount].subName;
    NSString *fullName = [NSString stringWithFormat:@"%@的%@",[WCUserObject getLoginUserNickName],role];

    [msg setMessageFrom:fullName];
    NSXMLElement *body = [message elementForName:@"body"];
    NSString *xesMessageStr = [[body stringValue] stringByDecodingHTMLEntities];
    NSError *error;
    NSXMLElement *user = [[NSXMLElement alloc]initWithXMLString:xesMessageStr error:&error];
    NSXMLElement *msgelement = [user elementForName:@"msg"];
    NSString *msgType = [[msgelement attributeForName:@"mtype"] stringValue];
    NSString *content ;
    
    
    [msg setMessageTo:strs[0]];
    [msg setMessageRoom:[roomXMPPID componentsSeparatedByString:@"@"][0]];
    [msg setMessageSendXMPPid:[[NSUserDefaults standardUserDefaults]objectForKey:kXMPPmyJID]];
    [msg setHeadimg:[[NSUserDefaults standardUserDefaults]objectForKey:kMY_USER_Head] ];
    [msg setMessageStatus:kWCMessageSending];
    [msg setMessageReadFlag:kWCMessageReadStatusRead];
    [msg setMessageId:[NSString stringWithFormat:@"%llu",interval]];
    if([msgType isEqualToString:@"text"])
    {
        [msg setMessageType:kWCMessageTypePlain];
        content = [[msgelement elementForName:@"content"] stringValue];

        [msg setMessageContent:content];
        if (![WCMessageObject save:msg]) {
            NSLog(@"%@",@"no save");
        };
    }else
    {
        //[msg setMessageType:kWCMessageTypeImage];
        NSXMLElement *img = [msgelement elementForName:@"imgs"];
        NSString *imageLocalPath = [[img elementForName:@"small"] stringValue];
        NSString *imageURLPath = [[img elementForName:@"big"] stringValue];
        [msg setImageLocalPath:imageLocalPath];
        [msg setImageURLPath:imageURLPath];
        
    }
    XMPPRoom *roomConnection = [_roomConnections objectForKey:roomXMPPID];
   [roomConnection sendXESMessage:message];
}

#pragma mark --------配置XML流---------
- (void)setupStream
{
	NSAssert(xmppStream == nil, @"Method setupStream invoked multiple times");
	
	    
	xmppStream = [[XMPPStream alloc] init];
	
#if !TARGET_IPHONE_SIMULATOR
	{
        xmppStream.enableBackgroundingOnSocket = YES;
	}
#endif
	
	xmppAutoPing = [[XMPPAutoPing alloc]init];
	
	xmppReconnect = [[XMPPReconnect alloc] init];
    
		// Setup capabilities
	//
	// The XMPPCapabilities module handles all the complex hashing of the caps protocol (XEP-0115).
	// Basically, when other clients broadcast their presence on the network
	// they include information about what capabilities their client supports (audio, video, file transfer, etc).
	// But as you can imagine, this list starts to get pretty big.
	// This is where the hashing stuff comes into play.
	// Most people running the same version of the same client are going to have the same list of capabilities.
	// So the protocol defines a standardized way to hash the list of capabilities.
	// Clients then broadcast the tiny hash instead of the big list.
	// The XMPPCapabilities protocol automatically handles figuring out what these hashes mean,
	// and also persistently storing the hashes so lookups aren't needed in the future.
	//
	// Similarly to the roster, the storage of the module is abstracted.
	// You are strongly encouraged to persist caps information across sessions.
	//
	// The XMPPCapabilitiesCoreDataStorage is an ideal solution.
	// It can also be shared amongst multiple streams to further reduce hash lookups.
	
	// Activate xmpp modules
    _xmpprRoomStorage = [[XMPPRoomCoreDataStorage alloc]init];
    
    xmppRosterStorage = [[XMPPRosterCoreDataStorage alloc] init];

	xmppRoster = [[XMPPRoster alloc] initWithRosterStorage:xmppRosterStorage];
	
	xmppRoster.autoFetchRoster = YES;
	xmppRoster.autoAcceptKnownPresenceSubscriptionRequests = YES;
    
	[xmppReconnect         activate:xmppStream];
    [xmppRoster            activate:xmppStream];
    [xmppAutoPing activate:xmppStream];
    [xmppAutoPing addDelegate:self delegateQueue:dispatch_get_main_queue()];
    xmppAutoPing.respondsToQueries = YES;
    xmppAutoPing.pingInterval =2 ;
    
	// Add ourself as a delegate to anything we may be interested in
    
	[xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];

	// Optional:
	//
	// Replace me with the proper domain and port.
	// The example below is setup for a typical google talk account.
	//
	// If you don't supply a hostName, then it will be automatically resolved using the JID (below).
	// For example, if you supply a JID like 'user@quack.com/rsrc'
	// then the xmpp framework will follow the xmpp specification, and do a SRV lookup for quack.com.
	//
	// If you don't specify a hostPort, then the default (5222) will be used.
	
	[xmppStream setHostName:kXMPPHost];
	[xmppStream setHostPort:5222];
	
    
   
    
	// You may need to alter these settings depending on the server you're connecting to
	allowSelfSignedCertificates = NO;
	allowSSLHostNameMismatch = NO;
    
    
    if (![self connect]) {
//        [[[UIAlertView alloc]initWithTitle:@"服务器连接失败" message:@"ps:本demo服务器非24小时开启，若急需请QQ 109327402" delegate:self cancelButtonTitle:@"ok" otherButtonTitles: nil]show];
    };
}

-(void)joinRoom:(NSString *)roomID nickname:(NSString *)name
{
    if ([self connect]) {
        if(!_roomConnections)
        {
            _roomConnections = [[NSMutableDictionary alloc]init];
        }
        //该链接不存在
        if(![_roomConnections objectForKey:roomID])
        {
            XMPPJID *roomXMPPJID = [XMPPJID jidWithString:roomID];
            XMPPRoom *xmppRoom = [[XMPPRoom alloc]initWithRoomStorage:_xmpprRoomStorage jid:roomXMPPJID dispatchQueue:dispatch_get_main_queue()];
            [xmppRoom activate:xmppStream];
            [xmppRoom addDelegate:self delegateQueue:dispatch_get_main_queue()];
            NSXMLElement *history = [[NSXMLElement alloc]initWithName:@"history"];
            [history addAttributeWithName:@"maxstanzas" stringValue:@"0"];
            [xmppRoom joinRoomUsingNickname:name history:history password:nil];
            [xmppRoom fetchConfigurationForm];
            [_roomConnections setObject:xmppRoom forKey:roomID];
        }else
        {
//            XMPPRoom *xmppRoom = [_roomConnections objectForKey:roomID];
//            if(![xmppRoom isJoined])
//            {
//                XMPPJID *roomXMPPJID = [XMPPJID jidWithString:roomID];
//                XMPPRoom *xmppRoombak = [[XMPPRoom alloc]initWithRoomStorage:_xmpprRoomStorage jid:roomXMPPJID dispatchQueue:dispatch_get_main_queue()];
//                [xmppRoombak activate:xmppStream];
//                [xmppRoombak addDelegate:self delegateQueue:dispatch_get_main_queue()];
//                NSXMLElement *history = [[NSXMLElement alloc]initWithName:@"history"];
//                [history addAttributeWithName:@"maxstanzas" stringValue:@"0"];
//                [xmppRoombak joinRoomUsingNickname:name history:history password:nil];
//                [xmppRoombak fetchConfigurationForm];
//                [_roomConnections setObject:xmppRoombak forKey:roomID];
//            }
        }
    }
}




- (void)xmppRoomDidCreate:(XMPPRoom *)sender{
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppRoomDidJoin:(XMPPRoom *)sender{
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}
- (void)teardownStream
{
	[xmppStream removeDelegate:self];
	
	[xmppReconnect         deactivate];
	
	[xmppStream disconnect];
	
	xmppStream = nil;
	xmppReconnect = nil;
}

// It's easy to create XML elments to send and to read received XML elements.
// You have the entire NSXMLElement and NSXMLNode API's.
//
// In addition to this, the NSXMLElement+XMPP category provides some very handy methods for working with XMPP.
//
// On the iPhone, Apple chose not to include the full NSXML suite.
// No problem - we use the KissXML library as a drop in replacement.
//
// For more information on working with XML elements, see the Wiki article:
// http://code.google.com/p/xmppframework/wiki/WorkingWithElements

- (void)goOnline
{
	XMPPPresence *presence = [XMPPPresence presence]; // type="available" is implicit
	
	[xmppStream sendElement:presence];
}

- (void)goOffline
{
	XMPPPresence *presence = [XMPPPresence presenceWithType:@"unavailable"];
	
	[xmppStream sendElement:presence];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connect/disconnect
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)connect
{
	if (![xmppStream isDisconnected]) {
		return YES;
	}
    
	NSString *myJID = [[NSUserDefaults standardUserDefaults] stringForKey:kXMPPmyJID];
	NSString *myPassword = [[NSUserDefaults standardUserDefaults] stringForKey:kXMPPmyPassword];
    
	//
	// If you don't want to use the Settings view to set the JID,
	// uncomment the section below to hard code a JID and password.
	//
	// myJID = @"user@gmail.com/xmppframework";
	// myPassword = @"";
	
	if (myJID == nil || myPassword == nil) {
		return NO;
	}
    
	// ===这句注释掉 改成下面这句   [xmppStream setMyJID:[XMPPJID jidWithString:myJID]];
    //连接服务器
    [xmppStream setMyJID:[XMPPJID jidWithUser:myJID domain:xmppdomain resource:xmppResource]];
    password=myPassword;
    xmppAutoPing.targetJID = [XMPPJID jidWithUser:myJID domain:xmppdomain resource:xmppResource];
	NSError *error = nil;
	if (![xmppStream connect:&error])
	{
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error connecting"
		                                                    message:@"See console for error details."
		                                                   delegate:nil
		                                          cancelButtonTitle:@"Ok"
		                                          otherButtonTitles:nil];
		[alertView show];
        
		DDLogError(@"Error connecting: %@", error);
        
		return NO;
	}
    
	return YES;
}

- (void)disconnect
{
	[self goOffline];
	[xmppStream disconnect];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UIApplicationDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	// Use this method to release shared resources, save user data, invalidate timers, and store
	// enough application state information to restore your application to its current state in case
	// it is terminated later.
	//
	// If your application supports background execution,
	// called instead of applicationWillTerminate: when the user quits.
	
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    
#if TARGET_IPHONE_SIMULATOR
	DDLogError(@"The iPhone simulator does not process background network traffic. "
			   @"Inbound traffic is queued until the keepAliveTimeout:handler: fires.");
#endif
    
	if ([application respondsToSelector:@selector(setKeepAliveTimeout:handler:)])
	{
		[application setKeepAliveTimeout:600 handler:^{
			
			DDLogVerbose(@"KeepAliveHandler");
			
			// Do other keep alive stuff here.
		}];
	}
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (NSManagedObjectContext *)managedObjectContext_roster
{
	return [xmppRosterStorage mainThreadManagedObjectContext];
}
// Returns the URL to the application's Documents directory.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStream:(XMPPStream *)sender socketDidConnect:(GCDAsyncSocket *)socket
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStream:(XMPPStream *)sender willSecureWithSettings:(NSMutableDictionary *)settings
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
	
	if (allowSelfSignedCertificates)
	{
		[settings setObject:[NSNumber numberWithBool:YES] forKey:(NSString *)kCFStreamSSLAllowsAnyRoot];
	}
	
	if (allowSSLHostNameMismatch)
	{
		[settings setObject:[NSNull null] forKey:(NSString *)kCFStreamSSLPeerName];
	}
	else
	{
		// Google does things incorrectly (does not conform to RFC).
		// Because so many people ask questions about this (assume xmpp framework is broken),
		// I've explicitly added code that shows how other xmpp clients "do the right thing"
		// when connecting to a google server (gmail, or google apps for domains).
		
		NSString *expectedCertName = nil;
		
		NSString *serverDomain = xmppStream.hostName;
		NSString *virtualDomain = [xmppStream.myJID domain];
		
		if ([serverDomain isEqualToString:@"talk.google.com"])
		{
			if ([virtualDomain isEqualToString:@"gmail.com"])
			{
				expectedCertName = virtualDomain;
			}
			else
			{
				expectedCertName = serverDomain;
			}
		}
		else if (serverDomain == nil)
		{
			expectedCertName = virtualDomain;
		}
		else
		{
			expectedCertName = serverDomain;
		}
		
		if (expectedCertName)
		{
			[settings setObject:expectedCertName forKey:(NSString *)kCFStreamSSLPeerName];
		}
	}
}

- (void)xmppStreamDidSecure:(XMPPStream *)sender
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStreamDidConnect:(XMPPStream *)sender
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
	
    DDLogInfo(@"链接成功==============================");
	isXmppConnected = YES;
	
	NSError *error = nil;
	
	if (![xmppStream authenticateWithPassword:password error:&error])
	{
		DDLogError(@"Error authenticating: %@", error);
	}
    [self stopReConnectTimer];
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
	NSLog(@"real success");
	[self goOnline];
    [xmppRoster fetchRoster];
    [[NSNotificationCenter defaultCenter]postNotificationName:ConnectionReach object:nil];
    [[NSNotificationCenter defaultCenter]postNotificationName:joinRoomNotification object:nil];

}

- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    [[NSNotificationCenter defaultCenter]postNotificationName:ConnectionNoReach object:nil];
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
	DDLogVerbose(@"%@: %@ - %@", THIS_FILE, THIS_METHOD, [iq elementID]);
	
    NSLog(@"收到好友iq:%@",iq);
    
    
	return NO;
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    //判断是否是message消息 并且是发送给我的
    NSString *messageSender = [message fromStr];
    NSArray  *senderArr = [messageSender componentsSeparatedByString:@"/"];
    NSString *sendeName = @"anyone" ;
    NSString *sendXmppid ;
    if([senderArr count]<2)
    {
        sendXmppid = @"system";
    }else{
        sendXmppid = senderArr[1];
    }
    //是消息且不是我发的
    if([[message name] isEqualToString:@"message"] && ![sendXmppid isEqualToString:[[NSUserDefaults standardUserDefaults]objectForKey:kXMPPmyJID] ]  )
    {
        //判断是否是groupchat
        NSString *chatType = [[message attributeForName:@"type"] stringValue];
            if([chatType isEqualToString:@"groupchat"])
            {
                //判断是否是我们的消息
                NSError *error;
                NSXMLElement *body = [message elementForName:@"body"] ;
                NSString *xesMessageStr = [[body stringValue] stringByDecodingHTMLEntities];
                NSXMLElement *user = [[NSXMLElement alloc]initWithXMLString:xesMessageStr error:&error];;
                if(user)
                {
                    //自定义标签
                    NSXMLElement *msgelement = [user elementForName:@"msg"];
                    NSString *msgType = [[msgelement attributeForName:@"mtype"] stringValue];
                    NSString *content ;
                    sendeName = [user attributeStringValueForName:@"nickname"];
                    if(![msgType isEqualToString:@"group"])
                    {
                        NSArray *roomArr=[messageSender componentsSeparatedByString:@"@"];
                        //NSString *receiverStr = [message toStr];
                        //NSArray *receiverArr = [receiverStr componentsSeparatedByString:@"@"];
                        WCMessageObject *msg=[WCMessageObject messageWithType:kWCMessageTypePlain];
                        
                        NSString *dateStr = [msgelement attributeStringValueForName:@"mid"];
                        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                        [f setNumberStyle:NSNumberFormatterDecimalStyle];
                        NSNumber * myNumber = [f numberFromString:dateStr];
                        NSTimeInterval da = [myNumber doubleValue]/1000;
                        NSDate *date = [NSDate dateWithTimeIntervalSince1970:da];
                        [msg setMessageDate:date];
                        [msg setMessageFrom:sendeName];
                        [msg setMessageRoom:roomArr[0]];
                        [msg setHeadimg:[user attributeStringValueForName:@"headimg"]];
                        [msg setMessageSendXMPPid:sendXmppid];
                        if([msgType isEqualToString:@"text"])
                        {
                            [msg setMessageType:kWCMessageTypePlain];
                            content = [[msgelement elementForName:@"content"] stringValue];
                        }else
                        {
                            [msg setMessageType:kWCMessageTypeImage];
                            NSXMLElement *imgs = [msgelement elementForName:@"imgs"];
                            NSString *imageLocalPath = [[imgs elementForName:@"small"] stringValue];
                            NSString *imageURLPath = [[imgs elementForName:@"big"] stringValue];
                            [msg setImageLocalPath:imageLocalPath];
                            [msg setImageURLPath:imageURLPath];
                        }
                        long long timeval = [[NSNumber numberWithDouble:[date timeIntervalSince1970]*1000]longLongValue];
                        [msg setMessageId:[NSString stringWithFormat:@"%llu",timeval]];
                        [msg setMessageContent:content];
                        [msg setMessageStatus:kWCMessageDone];
                        DDLogInfo(@"%@",[[NSUserDefaults standardUserDefaults] objectForKey:kMY_USER_ID]);
                        [msg setMessageTo: [WCUserObject getLoginUserId]];
                        [msg setMessageReadFlag:kWCMessageReadStatusUnRead];
                        [WCMessageObject save:msg ];
                        
                    }else if([msgType isEqualToString:@"group"])
                    {
                        //content = [[message elementForName:@"body"] stringValue ];
                        //踢人操作
                        SystemNotificationObject *notification = [[SystemNotificationObject alloc]init];
                        sendeName = [user attributeStringValueForName:@"nickname"];
                        notification.notificationFrom = sendeName;
                        notification.notificationStatus = kWCSystmNotificationUnRead;
                        NSString *dateStr = [msgelement attributeStringValueForName:@"mid"];
                        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                        [f setNumberStyle:NSNumberFormatterDecimalStyle];
                        NSNumber * myNumber = [f numberFromString:dateStr];
                        NSTimeInterval da = [myNumber doubleValue]/1000;
                        NSDate *date = [NSDate dateWithTimeIntervalSince1970:da];
                        notification.notificationDate = date;
                        notification.notificationType = kWCSystmNotificationKick;
                        NSXMLElement *contentNode = [msgelement elementForName:@"content"];
                        NSString *userId = [contentNode attributeStringValueForName:@"user"];
                        if( userId && ![userId isEqualToString:@""])
                        {
                            notification.userId = [contentNode attributeStringValueForName:@"user"];
                            //发送踢人消息
                            [SystemNotificationObject save:notification];

                        }
                        
                            WCMessageObject *messageObj = [[WCMessageObject alloc]init];
                            messageObj.messageType = kWCMessageTypeNotification;
                            messageObj.messageContent = [contentNode stringValue];
                            messageObj.messageFrom = sendeName;
                            messageObj.messageRoom = notification.roomId;
                            messageObj.messageDate = date;
                            [WCMessageObject save:messageObj];
                        
                    }

                }
                
            }else if ([chatType isEqualToString:@"headline"])
            {
                //是系统消息
                NSError *error;
                NSXMLElement *body = [message elementForName:@"body"] ;
               
                NSString *xesMessageStr = [[body stringValue] stringByDecodingHTMLEntities];
                NSXMLElement *user = [[NSXMLElement alloc]initWithXMLString:xesMessageStr error:&error];
                if(user)
                {
                     SystemNotificationObject *notification = [[SystemNotificationObject alloc]init];
                    notification.notificationStatus = kWCSystmNotificationUnRead;
                    NSXMLElement *msgelement = [user elementForName:@"msg"];
                    sendeName = [user attributeStringValueForName:@"nickname"];
                    NSString *dateStr = [msgelement attributeStringValueForName:@"mid"];
                    NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                    [f setNumberStyle:NSNumberFormatterDecimalStyle];
                    NSNumber * myNumber = [f numberFromString:dateStr];
                    NSTimeInterval da = [myNumber doubleValue]/1000;
                    NSDate *date = [NSDate dateWithTimeIntervalSince1970:da];
                    notification.notificationHead = [[user attributeForName:@"headimg"] stringValue];
                    NSXMLElement *contentNode = [msgelement elementForName:@"content"];
                    NSString *msgType = [[msgelement attributeForName:@"mtype"] stringValue];
                    if ([msgType isEqualToString:@"system"]) {
                        notification.notificationType = kWCSystmNotificationPlain;
                    }else if([msgType isEqualToString:@"ban"])
                    {
                        notification.notificationType = kWCSystmNotificationBan;
                        notification.roomId = [contentNode attributeStringValueForName:@"roomid"];
                        //发送消息禁言

                        [GroupObject banSpeak:notification.roomId];
                    }else if ([msgType isEqualToString:@"unban"])
                    {
                        notification.notificationType = kWCSystmNotificationUnBan;
                        notification.roomId = [contentNode attributeStringValueForName:@"roomid"];
                        //发送消息解禁
                        [GroupObject reCoverSpeak:notification.roomId];
                    }else if ([msgType isEqualToString:@"pass"])
                    {
                        notification.notificationType = kWCSystmNotificationPass;
                        notification.roomId = [contentNode attributeStringValueForName:@"roomid"];
                        //发送消息通过
                        [[NSNotificationCenter defaultCenter]postNotificationName:getRemoteGroupListNotification object:nil];
                    }
                    notification.notificationFrom = sendeName;
                    notification.content = [contentNode stringValue];
                    notification.notificationDate = date;
                    [SystemNotificationObject save:notification];
                }
            }
    }
	
}

- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence
{
	DDLogVerbose(@"%@: %@ - %@", THIS_FILE, THIS_METHOD, [presence fromStr]);


}

- (void)xmppStream:(XMPPStream *)sender didReceiveError:(id)error
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
    DDLogVerbose(@"========%@",error);
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error
{
	DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
	NSAssert(1!=0, @"断开连接");
	if (!isXmppConnected)
	{
		DDLogError(@"Unable to connect to server. Check xmppStream.hostName");
	}
    //开始重连
    [self startReConnectTimer];
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPRosterDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppRoster:(XMPPRoster *)sender didReceivePresenceSubscriptionRequest:(XMPPPresence *)presence
{
    
    XMPPJID *jid=[XMPPJID jidWithString:[presence stringValue]];
    [xmppRoster acceptPresenceSubscriptionRequestFrom:jid andAddToRoster:YES];
}

- (void)addSomeBody:(NSString *)userId
{
    [xmppRoster subscribePresenceToUser:[XMPPJID jidWithString:[NSString stringWithFormat:@"%@@hcios.com",userId]]];
}

-(void)fetchUser:(NSString*)userId
{
    UIAlertView *av=[[UIAlertView alloc]initWithTitle:@"加载中" message:@"刷新好友列表中，请稍候" delegate:self cancelButtonTitle:@"ok" otherButtonTitles: nil];
    [av show];
    
    //此API使用方式请查看www.hcios.com:8080/user/findUser.html
    ASIFormDataRequest *request=[ASIFormDataRequest requestWithURL:API_BASE_URL(@"servlet/GetUserDetailServlet")];
    
    [request setPostValue:userId forKey:@"userId"];
    [request setDelegate:self];
    [request setDidFinishSelector:@selector(requestSuccess:)];
    [request setDidFailSelector:@selector(requestError:)];
    [request startAsynchronous];
}
-(void)requestSuccess:(ASIFormDataRequest*)request
{
    NSLog(@"response:%@",request.responseString);
    SBJsonParser *paser=[[SBJsonParser alloc]init];
    NSDictionary *rootDic=[paser objectWithString:request.responseString];
    int resultCode=[[rootDic objectForKey:@"result_code"]intValue];
    if (resultCode==1) {
        NSDictionary *dic=[rootDic objectForKey:@"data"];
        WCUserObject *user=[WCUserObject userFromDictionary:dic];
        [WCUserObject saveNewUser:user];
    }
    
}
-(void)requestError:(ASIFormDataRequest*)request
{
    
}

#pragma mark xmppAutopingDelegate
- (void)xmppAutoPingDidSendPing:(XMPPAutoPing *)sender

{
    NSAssert(1!=0, @"xmppAutoPingDidSendPing");
    NSLog(@"- (void)xmppAutoPingDidSendPing:(XMPPAutoPing *)sender");
    
}

- (void)xmppAutoPingDidReceivePong:(XMPPAutoPing *)sender

{
    NSAssert(1!=0, @"xmppAutoPingDidReceivePong");
    NSLog(@"- (void)xmppAutoPingDidReceivePong:(XMPPAutoPing *)sender");
    [self stopReConnectTimer];
    
}



- (void)xmppAutoPingDidTimeout:(XMPPAutoPing *)sender

{
    NSAssert(1!=0, @"xmppAutoPingDidTimeout");
    NSLog(@"- (void)xmppAutoPingDidTimeout:(XMPPAutoPing *)sender");

    [self startReConnectTimer];
    
}

@end
