import 'package:flutter_test/flutter_test.dart';
import 'package:weight_buddy/config.dart';

/// The Settings screen links to these; they must point at the public site's
/// routes and stay in step with the embedded site (site.go / routes.ts).
void main() {
  test('legal links derive from the site base URL', () {
    expect(kPrivacyUrl, '$kSiteBaseUrl/privacy');
    expect(kTermsUrl, '$kSiteBaseUrl/terms');
    expect(kDeleteAccountUrl, '$kSiteBaseUrl/delete-account');

    expect(Uri.parse(kPrivacyUrl).path, '/privacy');
    expect(Uri.parse(kTermsUrl).path, '/terms');
    expect(Uri.parse(kDeleteAccountUrl).path, '/delete-account');
  });
}
