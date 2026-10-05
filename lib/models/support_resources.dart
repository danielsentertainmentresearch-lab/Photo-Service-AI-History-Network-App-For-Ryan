// The Support page's resources (owner, 6 Oct 2026). Harm reduction is the
// ground rule: no judgement, nothing to qualify for, and the person in
// distress stays in control. Every number and link here must be checked by
// the owner before launch (docs/LAUNCH_CHECKLIST.md, "Support resources").

/// How a resource can be reached.
enum ReachKind { call, text, web }

class Reach {
  final ReachKind kind;

  /// What the button says ("Call 988", "Text HOME to 741741").
  final String label;

  /// The number to call or text, or the web address.
  final String target;

  /// For texts: the message to start with ("HOME").
  final String? body;

  const Reach.call(this.label, this.target)
    : kind = ReachKind.call,
      body = null;
  const Reach.text(this.label, this.target, [this.body])
    : kind = ReachKind.text;
  const Reach.web(this.label, this.target) : kind = ReachKind.web, body = null;

  /// The link that opens the phone, messages or browser.
  Uri get uri => switch (kind) {
    ReachKind.call => Uri(scheme: 'tel', path: target),
    ReachKind.text => Uri(
      scheme: 'sms',
      path: target,
      queryParameters: body == null ? null : {'body': body},
    ),
    ReachKind.web => Uri.parse(target),
  };
}

class SupportResource {
  final String name;

  /// One plain line on what it is.
  final String about;
  final List<Reach> reach;

  const SupportResource(this.name, this.about, this.reach);
}

class SupportSection {
  final String title;
  final List<SupportResource> resources;

  const SupportSection(this.title, this.resources);
}

/// The crisis line and emergency number shown first, big, for a country.
class CrisisFirst {
  final String country;
  final SupportResource crisisLine;
  final String emergency;

  const CrisisFirst(this.country, this.crisisLine, this.emergency);
}

const _lifeline988 = SupportResource(
  '988 Suicide & Crisis Lifeline',
  'Free and confidential, any time. For any kind of crisis, not only suicide.',
  [Reach.call('Call 988', '988'), Reach.text('Text 988', '988')],
);

/// The first thing on the page, by the phone's country (ISO code).
CrisisFirst crisisFirstFor(String? countryCode) =>
    switch (countryCode?.toUpperCase()) {
      'US' => const CrisisFirst('United States', _lifeline988, '911'),
      'CA' => const CrisisFirst('Canada', _lifeline988, '911'),
      'GB' => const CrisisFirst(
        'United Kingdom',
        SupportResource(
          'Samaritans',
          'Free, any time, to talk about anything.',
          [Reach.call('Call 116 123', '116123')],
        ),
        '999',
      ),
      'IE' => const CrisisFirst(
        'Ireland',
        SupportResource(
          'Samaritans',
          'Free, any time, to talk about anything.',
          [Reach.call('Call 116 123', '116123')],
        ),
        '112',
      ),
      'AU' => const CrisisFirst(
        'Australia',
        SupportResource('Lifeline', 'Crisis support any time.', [
          Reach.call('Call 13 11 14', '131114'),
        ]),
        '000',
      ),
      'NZ' => const CrisisFirst(
        'New Zealand',
        SupportResource('1737', 'Free call or text, any time, to talk.', [
          Reach.call('Call 1737', '1737'),
          Reach.text('Text 1737', '1737'),
        ]),
        '111',
      ),
      _ => const CrisisFirst(
        'Your country',
        SupportResource(
          'Find A Helpline',
          'Free, confidential helplines in your country.',
          [Reach.web('Find a helpline', 'https://findahelpline.com')],
        ),
        '112',
      ),
    };

/// Everything below the crisis line, in order. US services unless named.
const supportSections = [
  SupportSection('If someone else is a danger to you', [
    SupportResource(
      'National Domestic Violence Hotline',
      'Help with safety planning, any time, including if the danger is a '
          'partner or ex.',
      [
        Reach.call('Call 1-800-799-7233', '18007997233'),
        Reach.text('Text START to 88788', '88788', 'START'),
      ],
    ),
    SupportResource(
      'RAINN National Sexual Assault Hotline',
      'Confidential support after sexual violence, any time.',
      [Reach.call('Call 1-800-656-4673', '18006564673')],
    ),
    SupportResource(
      'Childhelp National Child Abuse Hotline',
      'For children and adults worried about a child.',
      [Reach.call('Call 1-800-422-4453', '18004224453')],
    ),
    SupportResource(
      'National Human Trafficking Hotline',
      'If someone is being forced to work or trade sex.',
      [
        Reach.call('Call 1-888-373-7888', '18883737888'),
        Reach.text('Text 233733', '233733'),
      ],
    ),
  ]),
  SupportSection('More crisis lines', [
    SupportResource(
      'Crisis Text Line',
      'Text with a trained counselor, any time.',
      [Reach.text('Text HOME to 741741', '741741', 'HOME')],
    ),
    SupportResource(
      'Veterans Crisis Line',
      'For veterans, service members and the people who love them.',
      [
        Reach.call('Call 988, then press 1', '988'),
        Reach.text('Text 838255', '838255'),
      ],
    ),
    SupportResource('The Trevor Project', 'For LGBTQ+ young people.', [
      Reach.call('Call 1-866-488-7386', '18664887386'),
      Reach.text('Text START to 678-678', '678678', 'START'),
    ]),
    SupportResource(
      'Trans Lifeline',
      'Peer support run by and for trans people.',
      [Reach.call('Call 1-877-565-8860', '18775658860')],
    ),
  ]),
  SupportSection('Mental health support', [
    SupportResource(
      'NAMI HelpLine',
      'Information, support and next steps for you or someone you love.',
      [
        Reach.call('Call 1-800-950-6264', '18009506264'),
        Reach.text('Text "helpline" to 62640', '62640', 'helpline'),
      ],
    ),
    SupportResource(
      'SAMHSA National Helpline',
      'Free, confidential, any time: treatment and support for mental health '
          'and substance use.',
      [
        Reach.call('Call 1-800-662-4357', '18006624357'),
        Reach.web('Find treatment near you', 'https://findtreatment.gov'),
      ],
    ),
    SupportResource(
      'Disaster Distress Helpline',
      'After a disaster or any traumatic event.',
      [Reach.call('Call 1-800-985-5990', '18009855990')],
    ),
  ]),
  SupportSection('Using drugs more safely', [
    SupportResource(
      'Never Use Alone',
      'If you use, someone stays on the line and sends help to you if you '
          'stop responding. No judgement.',
      [Reach.call('Call 1-800-484-3731', '18004843731')],
    ),
    SupportResource(
      'Naloxone (Narcan)',
      'Reverses an opioid overdose. Sold without a prescription at most US '
          'pharmacies, and free by mail from NEXT Distro.',
      [Reach.web('Get naloxone', 'https://nextdistro.org')],
    ),
    SupportResource(
      'Poison Control',
      'For an overdose or anything swallowed, any time.',
      [Reach.call('Call 1-800-222-1222', '18002221222')],
    ),
  ]),
];

/// A short grounding exercise, for when things feel like too much.
const groundingSteps = [
  'Name 5 things you can see.',
  'Notice 4 things you can feel, like your feet on the floor.',
  'Listen for 3 things you can hear.',
  'Find 2 things you can smell.',
  'Notice 1 thing you can taste.',
];
