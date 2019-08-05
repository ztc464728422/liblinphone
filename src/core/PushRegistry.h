#include <PushKit/PushKit.h>
#include <PushKit/PKPushRegistry.h>
#include <UserNotifications/UserNotifications.h>
#include <UIKit/UIKit.h>

// TODO: Remove me
#include "private.h"
@interface RegistryDelegate : NSObject <PKPushRegistryDelegate> {
	std::shared_ptr<LinphonePrivate::Core> pcore;
}
- (void)setCore:(std::shared_ptr<LinphonePrivate::Core> )core;
@end
