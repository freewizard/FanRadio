//
//  DoubanRadio.m
//  FanRadio
//
//  Created by Du Song on 10-6-17.
//  Copyright 2010 rollingcode.org. All rights reserved.
//

#import "DoubanRadio.h"
#import "CJSONDeserializer.h"
#import "Speaker.h"
#import "DataLoader.h"
#import "DataPoster.h"
#import "RegexKitLite.h"
#import "SSGenericKeychainItem.h"

NSString * const SongReadyNotification = @"SongReady";
NSString * const LoginCheckedNotification = @"LoginChecked";

@implementation DoubanRadio

@synthesize channelId = _channelId;
@synthesize lastChannelId = _lastChannelId;
@synthesize sid = _sid;
@synthesize aid = _aid;
@synthesize liked = _liked;
@synthesize loginSuccess = _loginSuccess;
@synthesize title = _title;
@synthesize artist = _artist;
@synthesize url = _url;
@synthesize album = _album;
@synthesize cover = _cover;
@synthesize pageURL = _pageURL;
@synthesize username = _username;
@synthesize password = _password;
@synthesize nickname = _nickname;
@synthesize profilePage = _profilePage;
@synthesize lastRequestUrl = _lastRequestUrl;

//
//



static NSString *KeychainServiceName = @"FanRadio.Douban";

- (NSString *) username {
	NSString *username_ = [[NSUserDefaults standardUserDefaults] stringForKey:@"DoubanUsername"];
	return username_ ? username_ : @"";
}

- (void) setUsername:(NSString *)username_ {
	[[NSUserDefaults standardUserDefaults] setValue:username_ forKey:@"DoubanUsername"];
}

- (NSString *) password {
	NSString *username_ = [self username];
	if ([username_ length]==0) return @"";
	NSString *password_ = [SSGenericKeychainItem passwordForUsername:username_ serviceName:KeychainServiceName];
	NSLog(@"getPassword %@ for %@", password_, username_);
	return password_ ? password_ : @"";
}

- (void) setPassword:(NSString *)password_ {
	NSString *username_ = [self username];
	if ([username_ length]==0) return;
	if (!password_) password_=@"";
	NSLog(@"setPassword %@ for %@", password_, username_);
	[SSGenericKeychainItem setPassword:password_ forUsername:username_ serviceName:KeychainServiceName];
}

- (void)dealloc { 
	[_title release];
	[_artist release];
	[_url release];
	[_album release];
	[_cover release];
	[_pageURL release];
	[_username release];
	[_password release];
	[_nickname release];
	[_profilePage release];
	[_lastRequestUrl release];
	[super dealloc];
}

- (void)perform:(NSString *)action reload:(BOOL)r {
	NSString *url = [NSString stringWithFormat:@"http://douban.fm/j/mine/playlist?type=%@&channel=%lu&sid=%lu&aid=%lu&last_channel=%lu", 
					 action, _channelId, _sid, _aid, _lastChannelId];
	_lastChannelId = _channelId;
	if (r) {
		self.lastRequestUrl = url;
		[self performInternal:url];
	} else {
		[DataLoader load:url];
	}
}

- (void)performInternal:(NSString *)url_ {
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(songsFetched:) 
												 name:DataLoadedNotification 
											   object:[DataLoader load:url_]];
}

- (void)likeCurrent {
	[self perform:@"r" reload:NO];
}
- (void)unlikeCurrent {
	[self perform:@"u" reload:NO];
}
- (void)banCurrent {
	[self perform:@"b" reload:YES];
}
- (void)playNext {
	[self perform:@"s" reload:YES];
}
- (void)tuneChannel:(NSUInteger)newChannelId {
	_lastChannelId = _channelId;
	_channelId = newChannelId;
	[self playNext];
}

- (void)recheckLogin {
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(recheckLoginCleanUpDone:) 
												 name:DataLoadedNotification 
											   object:[DataLoader load:@"http://www.douban.com/accounts/logout" withCookie:@""]]; 
}

- (void)recheckLoginCleanUpDone:(NSNotification *)notification {
	[self checkLogin];
}

- (void)checkLogin {
	NSLog(@"checkLogin %@", self.username);
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(checkLoginComplete:) 
												 name:DataLoadedNotification 
											   object:[DataPoster post:@"http://www.douban.com/accounts/login" 
														 andParameters:[NSString stringWithFormat:@"form_email=%@&form_password=%@&redir=%@",
																		[self.username URLEncodeString], 
																		[self.password URLEncodeString], 
																		[@"http://douban.fm/login" URLEncodeString]]
													   ]];
}

- (void)checkLoginComplete:(NSNotification *)notification {
	NSData *data = [[notification userInfo] objectForKey:@"data"];
	NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSArray *matches = [NSArray arrayWithArray:[str arrayOfCaptureComponentsMatchedByRegex:@"<a href=\"(http://www\\.douban\\.com/people/[^\"]+/)\">([^<]+)</a>"]];
	NSLog(@"Parse login %@", matches);
	if ([matches count] == 1) {
		self.loginSuccess = YES;
		self.profilePage = [[matches objectAtIndex:0] objectAtIndex:1];
		self.nickname = [[matches objectAtIndex:0] objectAtIndex:2];
	} else {
		self.loginSuccess = NO;
		NSArray *matches2 = [NSArray arrayWithArray:[str arrayOfCaptureComponentsMatchedByRegex:@"<p class=\"attn\">([^<]+)</p>"]];
		if ([matches2 count] == 1) {
			NSLog(@"login failed: %@", [[matches2 objectAtIndex:0] objectAtIndex:1]);
		} else {
			NSLog(@"login failed with full dump:\n%@", str);
		}

	}
	[[NSNotificationCenter defaultCenter] postNotificationName:LoginCheckedNotification object:self];
	[str release];
}

- (void)songsFetched:(NSNotification *)notification {
	//NSString *responseString = [request responseString];
	//NSLog(@"FIN %@", responseString);
	[[NSNotificationCenter defaultCenter] removeObserver:self name:DataLoadedNotification object:[notification object]];
	NSData *data = [[notification userInfo] objectForKey:@"data"];
	NSError *error;
	NSDictionary *items = [[CJSONDeserializer deserializer] deserializeAsDictionary:data error:&error];
	NSArray *songs = [items objectForKey:@"song"];
	if (songs && [songs count]) {
		NSDictionary * song = [songs objectAtIndex:0];
		self.title = [song objectForKey:@"title"];
		self.artist = [song objectForKey:@"artist"];
		self.url = [song objectForKey:@"url"];
		self.album = [song objectForKey:@"albumtitle"];
		self.cover = [song objectForKey:@"picture"];
		self.pageURL = [NSString stringWithFormat:@"%@%@", @"http://music.douban.com", [song objectForKey:@"album"]];
		self.sid = [[song objectForKey:@"sid"] integerValue];
		self.aid = [[song objectForKey:@"aid"] integerValue];
		self.liked = [[song objectForKey:@"like"] boolValue];
		[[NSNotificationCenter defaultCenter] postNotificationName:SongReadyNotification object:self];
	} else {
		NSLog(@"Song list not loaded. %@", error);
		//TODO retry
	}
}

- (NSInteger) totalListenedTime {
	NSInteger time_ = [[NSUserDefaults standardUserDefaults] integerForKey:@"DoubanListenedTime"];
	return time_ > 0  ? time_ : 0;
}

- (void) setTotalListenedTime:(NSInteger)time_ {
	[[NSUserDefaults standardUserDefaults] setInteger:time_ forKey:@"DoubanListenedTime"];
}

- (NSInteger) totalListenedTracks {
	NSInteger tracks_ = [[NSUserDefaults standardUserDefaults] integerForKey:@"DoubanListenedTracks"];
	return tracks_>0 ? tracks_ : 0;
}

- (void) setTotalListenedTracks:(NSInteger)tracks_ {
	[[NSUserDefaults standardUserDefaults] setInteger:tracks_ forKey:@"DoubanListenedTracks"];
}

- (NSArray*) channelList {
	//TODO
	//[NSDictionary dictionaryWithObjectsAndKeys:<#(id)firstObject#>
}

@end
