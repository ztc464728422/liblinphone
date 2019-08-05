/*
 linphone
 Copyright (C) 2017 Belledonne Communications SARL

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#include "PushRegistry.h"
// TODO: Remove me
#include "private.h"

@implementation RegistryDelegate

- (void)setCore:(std::shared_ptr<LinphonePrivate::Core> )core {
	pcore = core;
}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(PKPushType)type {
	NSData *tokenData = credentials.token;
	if (tokenData != nil) {
		const unsigned char *tokenBuffer = (const unsigned char *)[tokenData bytes];
		NSMutableString *tokenString = [NSMutableString stringWithCapacity:[tokenData length] * 2];
		for (int i = 0; i < int([tokenData length]); ++i) {
			[tokenString appendFormat:@"%02X", (unsigned int)tokenBuffer[i]];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			linphone_core_set_push_notification_token(pcore->getCCore(), [tokenString UTF8String]);
		});
	}
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(NSString *)type {
	ms_message("[PushKit] Token invalidated");
	dispatch_async(dispatch_get_main_queue(), ^{linphone_core_set_push_notification_token(pcore->getCCore(),NULL);});
}

- (void)processPush:(NSDictionary *)userInfo {
	ms_message("[PushKit] Notification [%p] received with pay load : %s", userInfo, userInfo.description.UTF8String);
	//to avoid IOS to suspend the app before being able to launch long running task
	[self processRemoteNotification:userInfo];
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type withCompletionHandler:(void (^)(void))completion {
	[self processPush:payload.dictionaryPayload];
	dispatch_async(dispatch_get_main_queue(), ^{completion();});
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type {
	[self processPush:payload.dictionaryPayload];
}

- (void)processRemoteNotification:(NSDictionary *)userInfo {
	if (linphone_core_get_calls(pcore->getCCore())) {
		// if there are calls, obviously our TCP socket shall be working
		ms_warning("Notification [%p] has no need to be processed because there already is an active call.", userInfo);
		return;
	}

	NSDictionary *aps = [userInfo objectForKey:@"aps"];
	if (!aps) {
		ms_error("Notification [%p] was empy, it's impossible to process it.", userInfo);
		return;
	}

	NSString *loc_key = [aps objectForKey:@"loc-key"] ?: [[aps objectForKey:@"alert"] objectForKey:@"loc-key"];
	if (!loc_key) {
		ms_error("Notification [%p] has no loc_key, it's impossible to process it.", userInfo);
		return;
	}

  NSString *uuid = [NSString stringWithFormat:@"<urn:uuid:%@>", [NSString stringWithUTF8String:lp_config_get_string(pcore->getCCore()->config,"misc","uuid",NULL)]];
	NSString *sipInstance = [aps objectForKey:@"uuid"];
	if (sipInstance && uuid && ![sipInstance isEqualToString:uuid]) {
		ms_error("Notification [%p] was intended for another device, ignoring it.", userInfo);
		ms_error("My sip instance is: [%s], push was intended for: [%s].", uuid, [sipInstance UTF8String]);
		return;
	}

	LinphonePrivate::PlatformHelpers *iosHelper = getPlatformHelpers(pcore->getCCore());
	NSString *callId = [aps objectForKey:@"call-id"] ?: @"";
	if (callId && ([UIApplication sharedApplication].applicationState != UIApplicationStateActive))// && [self addLongTaskIDforCallID:callId])
		iosHelper->startPushLongRunningTask(loc_key.UTF8String, callId.UTF8String);

	// if we receive a push notification, it is probably because our TCP background socket was no more working.
	// As a result, break it and refresh registers in order to make sure to receive incoming INVITE or MESSAGE
	if (!linphone_core_is_network_reachable(pcore->getCCore())) {
		ms_message("Notification [%p] network is down, restarting it.", userInfo);
	}

	if ([callId isEqualToString:@""]) {
		// Present apn pusher notifications for info
		ms_message("Notification [%p] came from flexisip-pusher.", userInfo);
		if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_x_Max) {
			UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
			content.title = @"APN Pusher";
			content.body = @"Push notification received !";

			UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:@"call_request" content:content trigger:NULL];
			[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req withCompletionHandler:^(NSError * _Nullable error) {
				// Enable or disable features based on authorization.
				if (error) {
					ms_message("Error while adding notification request :");
					ms_message("%s", error.description.UTF8String);
				}
			}];
		} else {
			UILocalNotification *notification = [[UILocalNotification alloc] init];
			notification.repeatInterval = 0;
			notification.alertBody = @"Push notification received !";
			notification.alertTitle = @"APN Pusher";
			[[UIApplication sharedApplication] presentLocalNotificationNow:notification];
		}
	} else{
		//[LinphoneManager.instance addPushCallId:callId];
	}

	ms_message("Notification [%p] processed", userInfo);
}

@end
