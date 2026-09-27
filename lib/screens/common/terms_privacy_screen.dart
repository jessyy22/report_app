import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TermsPrivacyScreen extends StatefulWidget {
  const TermsPrivacyScreen({super.key});

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  bool _agreed = false;

  Future<void> _continue() async {
    if (!_agreed) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'rtoda_terms_agreed',
      true,
    );

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      '/login',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF119400),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'RTODA Agreement',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF119400)
                              .withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: Color(0xFF119400),
                          size: 45,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Center(
                      child: Text(
                        'Welcome to RTODA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF119400),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Center(
                      child: Text(
                        'Please read the following agreement before using the RTODA application.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    _section(
                      icon: Icons.info_outline_rounded,
                      title: 'About RTODA',
                      text:
                          'RTODA is a reporting and monitoring application designed to help commuters and tricycle drivers or operators submit and manage information related to tricycle operations in Vigan City.\n\n'
                          'The application provides features for account management, report submission, incident location, supporting evidence, notifications, driver or operator information, and monitoring by authorized personnel.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.description_outlined,
                      title: 'Terms of Use',
                      text:
                          'By using RTODA, you agree to use the application responsibly and only for its intended purposes.\n\n'
                          'You are responsible for providing accurate and truthful information when creating an account or submitting a report.\n\n'
                          'You must not submit false, misleading, abusive, offensive, or intentionally harmful reports or information.\n\n'
                          'You must not use RTODA to impersonate another person or to submit information without a legitimate reason.\n\n'
                          'RTODA provides a platform for report submission and monitoring. It does not replace the official procedures, investigation, or decisions of the appropriate authorities.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.person_outline_rounded,
                      title: 'Account Information',
                      text:
                          'RTODA may collect information needed to create and manage your account.\n\n'
                          'For commuters, this may include your name, phone number, email address, profile information, and identification information when required by the application.\n\n'
                          'For drivers or operators, this may include your name, phone number, email address, body number, driver license information, profile photo, and verification documents.\n\n'
                          'Driver or operator accounts may require verification by authorized RTODA or LGU personnel before access to certain features is provided.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.report_problem_outlined,
                      title: 'Report Submission',
                      text:
                          'When submitting a report, you may provide information such as the body number of the tricycle, type of violation or concern, incident date and time, location, description, contact information, and supporting evidence.\n\n'
                          'Submitted reports may be reviewed by authorized personnel for monitoring, verification, and appropriate action.\n\n'
                          'Users should only submit information and evidence that are relevant to the report.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.location_on_outlined,
                      title: 'Location Information',
                      text:
                          'RTODA may use location information when necessary for features such as identifying the location of a reported incident or supporting monitoring activities.\n\n'
                          'Location information should only be used for purposes related to the functions of the application.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.photo_camera_outlined,
                      title: 'Photos and Evidence',
                      text:
                          'Users may submit photos or other supporting evidence when creating a report or completing account verification.\n\n'
                          'Users are responsible for ensuring that submitted evidence is relevant to the purpose for which it is provided.\n\n'
                          'Avoid submitting unnecessary personal or sensitive information in photos or other evidence.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.lock_outline_rounded,
                      title: 'Privacy',
                      text:
                          'Information collected through RTODA may be used to provide application services, manage accounts, process reports, verify driver or operator information, support monitoring activities, and send relevant notifications.\n\n'
                          'Information submitted through the application may be accessed by authorized RTODA or LGU personnel when necessary for report review, verification, monitoring, and related operations.\n\n'
                          'RTODA will not intentionally request information that is unnecessary for the functions of the application.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notifications',
                      text:
                          'RTODA may send notifications related to account activity, report updates, emergency or safety alerts, and other important application information.\n\n'
                          'Notification availability may depend on your device settings and internet connection.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.security_outlined,
                      title: 'Responsible Use',
                      text:
                          'Users are expected to use RTODA respectfully and responsibly.\n\n'
                          'Any misuse of the application, including intentionally submitting false information, abusing the reporting system, or attempting to access another user’s account, may result in appropriate action by the authorized personnel.',
                    ),

                    const SizedBox(height: 18),

                    _section(
                      icon: Icons.account_balance_outlined,
                      title: 'Role of RTODA',
                      text:
                          'RTODA is intended to support the reporting and monitoring of tricycle operations in Vigan City.\n\n'
                          'The application does not independently determine violations, impose penalties, or replace the authority of the appropriate government office.\n\n'
                          'Reports submitted through RTODA are subject to review by authorized personnel and may be handled according to applicable procedures.',
                    ),

                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF119400)
                            .withOpacity(0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF119400)
                              .withOpacity(0.20),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _agreed,
                            activeColor:
                                const Color(0xFF119400),
                            onChanged: (value) {
                              setState(() {
                                _agreed = value ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Padding(
                              padding:
                                  EdgeInsets.only(top: 12),
                              child: Text(
                                'I have read and understood the RTODA Terms of Use and Privacy Policy. I agree to use the application responsibly and provide truthful information.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _agreed ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF119400),
                    disabledBackgroundColor:
                        Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    disabledForegroundColor:
                        Colors.grey.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'AGREE & CONTINUE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF119400),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}