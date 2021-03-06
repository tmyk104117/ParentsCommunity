//
//  WCXMPPManager.h
//  WeChat
//
//  Created by Reese on 13-8-10.
//  Copyright (c) 2013年 Reese. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "ParentsCommunity-Prefix.pch"
#import "XMPPFramework.h"
#import "XMPPRoom.h"
#import "XMPPRoomCoreDataStorage.h"
#import "XMPPAutoPing.h"
#import "Reachability.h"
@class XMPPMessage,XMPPRoster,XMPPRosterCoreDataStorage;
@interface WCXMPPManager : NSObject <UIApplicationDelegate>

{
    XMPPStream *xmppStream;
	XMPPReconnect *xmppReconnect;
    XMPPRoster *xmppRoster;
    XMPPRosterCoreDataStorage *xmppRosterStorage;
    XMPPRoomCoreDataStorage *_xmpprRoomStorage ;
   	NSString *password;
	
	BOOL allowSelfSignedCertificates;
	BOOL allowSSLHostNameMismatch;
	
	BOOL isXmppConnected;
    NSMutableDictionary *_roomConnections;
    NSTimer *reconnectTimer;
    XMPPAutoPing *xmppAutoPing;
    


}

- (NSManagedObjectContext *)managedObjectContext_roster;
@property (readonly, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;

- (void)saveContext;
- (NSURL *)applicationDocumentsDirectory;

- (BOOL)connect;
- (void)disconnect;
-(void)joinRoom:(NSString *)roomID nickname:(NSString *)name;
-(void)sendMessage2Room:(NSString *)roomXMPPID message:(XMPPMessage *)message;


+(WCXMPPManager*)sharedInstance;

-(void)reachabilityChanged:(NSNotification *)note;
#pragma mark -------配置XML流-----------

- (void)setupStream;
- (void)teardownStream;


#pragma mark ----------收发信息------------
- (void)goOnline;
- (void)goOffline;

- (void)sendMessage:(XMPPMessage *)aMessage;
- (void)addSomeBody:(NSString *)userId;


#pragma mark ---------文件传输-----------
-(void)sendFile:(NSData*)aData toJID:(XMPPJID*)aJID;
-(void)startReConnectTimer;
-(void)stopReConnectTimer;
-(void)reconnect:(NSTimer*)theTimer;
@end
