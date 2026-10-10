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
    case 'on_the_way':
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

String orderStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'on_the_way':
      return 'On the Way';
    case 'pending':
      return 'Pending';
    case 'approved':
      return 'Approved';
    case 'delivered':
      return 'Delivered';
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
