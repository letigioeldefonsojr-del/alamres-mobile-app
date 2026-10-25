import 'package:flutter/material.dart';

List<Map<String, dynamic>> getOrderItems(Map<String, dynamic> data) {
  final rawItems = data['items'] as List?;
  if (rawItems != null && rawItems.isNotEmpty) {
    return rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  if (data['productName'] != null) {
    return [
      {
        'productId': data['productId'],
        'productName': data['productName'],
        'imageUrl': data['imageUrl'],
        'flavor': data['flavor'],
        'amount': data['amount'],
        'unitPrice': data['unitPrice'],
        'subtotal': data['total'],
      },
    ];
  }

  return [];
}

Color orderStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'delivered':
      return const Color(0xFF2E6B3E);
    // Pickup orders never reach 'on_the_way' (per the admin side's own
    // lifecycle: pending -> approved -> ready_for_pickup -> delivered), so
    // reusing the same "almost there" blue for ready_for_pickup never
    // collides with it on a single order's own timeline.
    case 'on_the_way':
    case 'ready_for_pickup':
      return Colors.blue;
    case 'approved':
      return Colors.teal;
    case 'pending':
      return Colors.orange;
    case 'rejected':
    case 'cancelled':
    case 'undelivered':
      return Colors.redAccent;
    default:
      return Colors.grey;
  }
}

// [fulfillmentType] is optional and only changes the wording for the
// 'delivered' status, which the admin side repurposes to mean "picked up"
// for pickup orders - every other status reads the same either way.
// Passing it is never required: callers that don't have it on hand yet
// just get the delivery-flavored label, same as before this parameter
// existed.
String orderStatusLabel(String status, {String? fulfillmentType}) {
  final bool isPickup = fulfillmentType == 'pickup';
  switch (status.toLowerCase()) {
    case 'on_the_way':
      return 'On the Way';
    case 'pending':
      return 'Pending';
    case 'approved':
      return 'Approved';
    case 'ready_for_pickup':
      return 'Ready for Pickup';
    case 'delivered':
      return isPickup ? 'Picked Up' : 'Delivered';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'undelivered':
      return 'Unable to Deliver';
    default:
      return status;
  }
}
