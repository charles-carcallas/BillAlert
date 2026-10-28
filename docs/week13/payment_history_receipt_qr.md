# Payment date filtering and receipt QR codes

24 October 2026. Implements the missing parts of document requirements FR-25 and FR-29 in the application source.

## FR-25

Consumer → History → Payments → Payment dates opens a start/end date picker. Both endpoints are inclusive and use Philippine calendar dates derived from the receipt's actual payment timestamp. A payment for an August bill made in October is found in the October payment range.

The Payments tab now lists one row per receipt, shows the payment date and amount, and opens that exact receipt. A handover covering multiple bills appears once; multiple receipts for the same bill remain separate. Search by billing month or receipt number and newest/oldest sorting combine with the date range. Clear dates removes only the date filter. The Bills tab remains independent.

Filtering uses the already loaded payment history, including the existing offline cache. A failed refresh retains previously loaded receipts and displays the failure; a confirmed empty result clears them. It does not require a new server query or database schema change.

## FR-29

A shared QR widget renders the existing server-issued verification reference on the Consumer receipt, Cashier receipt details and newly issued Cashier receipt. The readable reference remains available. One receipt has one QR regardless of how many bills it covers.

The QR contains only the verification reference. Scanning reads that reference; it is not a new verification service, payment action, public receipt URL or camera scanner. Rendering works offline using `qr_flutter`. Black modules and a white quiet zone remain consistent in light and dark mode. Missing references show an unavailable message rather than generating a substitute.

## Validation

- Date-filter tests cover inclusive Philippine midnight boundaries, search intersection, ordering and repeated payments against the same bill.
- Widget tests cover applying, cancelling and clearing dates, empty results, receipt navigation and independence from the Bills tab, including a 320-pixel phone layout.
- Controller tests cover retained history after refresh failure and replacement by a confirmed empty result.
- Receipt tests exercise all three QR views in both themes at phone width and the missing-reference state. Existing receipt, payment-confirmation, notification navigation and offline-cache checks also pass.
- Rendered QR images were independently decoded to the expected reference in both themes. Physical-camera scanning and an installed Android build remain device checks.

Rebuild the app to use these changes. No backend migration is required.
