/// RevenueCat identity hook.
///
/// The app does not yet ship a purchase SDK — there is no paywall or
/// subscription today — so this is a no-op seam. When RevenueCat is added, wire
/// `Purchases.logIn` / `Purchases.logOut` here: the call sites already fire
/// whenever the backend user id changes (Google sign-in and sign-out), which is
/// exactly when the RevenueCat app user id must follow.
class RevenueCatIdentity {
  const RevenueCatIdentity();

  /// Associates purchases with our backend user id as the RevenueCat app user
  /// id, so an entitlement follows the user rather than the device.
  Future<void> logIn(String appUserId) async {}

  /// Clears the RevenueCat user, returning it to the anonymous state.
  Future<void> logOut() async {}
}
