import 'package:flutter/material.dart';

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const Color primaryGreen = Color(0xFF2E6B3E);

  static const List<Map<String, String>> _sections = [
    {
      'title': '1. Account Registration & Eligibility',
      'body':
          'Business Verification: Almares 328 primarily serves wholesale and business '
          'customers. We reserve the right to require valid business documentation '
          '(e.g., business license, tax exemption certificate) to open a wholesale account.\n\n'
          'Accuracy of Information: You agree to provide current, complete, and accurate '
          'billing and contact information. You are responsible for all activities that '
          'occur under your account.\n\n'
          'Termination: We reserve the right to suspend or terminate your account at our '
          'sole discretion if we suspect fraudulent activity or a breach of these Terms.',
    },
    {
      'title': '2. Orders & Minimum Quantities',
      'body':
          'Minimum Order Requirements: Wholesale orders may be subject to Minimum Order '
          'Quantities (MOQs) or minimum spending thresholds, which will be communicated '
          'at the time of purchase.\n\n'
          'Order Acceptance: All orders are subject to stock availability and acceptance '
          'by Almares 328. We reserve the right to limit the quantities of any products '
          'or services that we offer.\n\n'
          'Substitutions: In the event a product is out of stock, we will not substitute '
          'items without your prior consent unless a pre-approved substitution agreement '
          'is in place.',
    },
    {
      'title': '3. Pricing & Payment Terms',
      'body':
          'Pricing: All prices are subject to change without notice due to market '
          'fluctuations in agricultural and grocery commodities. The price charged will '
          'be the price in effect at the time the order is placed.\n\n'
          'Payment Methods: We accept cash, major credit cards, bank transfers, and '
          'approved business checks.\n\n'
          'Credit Terms: For businesses with approved credit accounts, payment is due '
          'strictly within the agreed-upon window (e.g., Net 15, Net 30). Late payments '
          'may accrue a late fee of 1.5% per month on the outstanding balance.\n\n'
          'Taxes: Prices do not include applicable taxes. Customers claiming tax '
          'exemption must provide a valid certificate prior to purchase.',
    },
    {
      'title': '4. Delivery & Receiving Goods',
      'body':
          'Delivery Windows: Delivery times are estimates. Almares 328 is not liable for '
          'delays caused by severe weather, traffic, or unforeseen logistical constraints.\n\n'
          'Receiving & Inspection: The customer or an authorized representative must be '
          'present to receive and sign for deliveries. Title and risk of loss pass to you '
          'upon delivery.\n\n'
          'Cold Chain Compliance: For perishable goods, Almares 328 guarantees temperature '
          'control up to the point of delivery. Once delivered and signed for, the '
          'customer assumes full responsibility for proper storage.',
    },
    {
      'title': '5. Returns, Refunds & Claims',
      'body':
          'Due to the nature of wholesale groceries and health safety standards, our '
          'return policy is strict:\n\n'
          'Perishable Goods (Produce, Meat, Dairy): Claims for damaged, spoiled, or '
          'missing perishable items must be reported within 24 hours of delivery or '
          'pickup.\n\n'
          'Non-Perishable Goods: Claims for dry goods, canned items, or packaging defects '
          'must be reported within 3 business days.\n\n'
          'Return Process: To initiate a claim, you must provide photographic evidence of '
          'the damaged goods and the original invoice. Refunds will be issued as store '
          'credit or back to the original payment method, at our discretion.',
    },
    {
      'title': '6. Limitation of Liability',
      'body':
          'To the fullest extent permitted by law, Almares 328 Wholesale Grocery Store '
          'shall not be liable for any indirect, incidental, special, consequential, or '
          'punitive damages, including without limitation, loss of profits, loss of data, '
          'or business interruption arising out of your use of our products or services. '
          'Our maximum liability to you for any claim shall not exceed the amount you '
          'paid for the specific goods in question.',
    },
    {
      'title': '7. Force Majeure',
      'body':
          'Almares 328 shall not be held responsible for failure or delay in fulfilling '
          'our obligations under these Terms if such failure is caused by events beyond '
          'our reasonable control, including natural disasters, pandemics, strikes, '
          'supply chain disruptions, or government regulations.',
    },
    {
      'title': '8. Modifications to Terms',
      'body':
          'We reserve the right to update or modify these Terms & Conditions at any time. '
          'Changes will take effect immediately upon being posted on our website or '
          'posted in-store. Your continued use of our Services constitutes acceptance of '
          'the revised Terms.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Terms & Conditions'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Almares 328 Terms & Conditions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Last Updated: July 15, 2026',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Almares 328 Wholesale Grocery Store. These Terms & Conditions '
              '("Terms") govern your use of our physical store, website, and delivery '
              'services (collectively, the "Services"). By registering an account, '
              'placing an order, or shopping with us, you agree to be bound by these Terms.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            for (final section in _sections) ...[
              Text(
                section['title']!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                section['body']!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}
