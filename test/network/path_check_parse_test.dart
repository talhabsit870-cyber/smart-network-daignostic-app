import 'package:flutter_test/flutter_test.dart';
import 'package:smart_network_diagnostic/network/path_check_result.dart';

void main() {
  group('parseTracertOutput', () {
    test('parses hop number, address, and RTT from a tracert -d line', () {
      const output = '''
Tracing route to speed.cloudflare.com [104.16.132.229]
over a maximum of 10 hops:

  1     3 ms     2 ms     2 ms  192.168.1.1
  2     *        *        *     Request timed out.
  3    12 ms    11 ms    10 ms  10.0.0.1
  4    45 ms    44 ms    43 ms  104.16.132.229

Trace complete.
''';
      final hops = parseTracertOutput(output);
      expect(hops.length, 4);

      expect(hops[0].hopNumber, 1);
      expect(hops[0].address, '192.168.1.1');
      expect(hops[0].rttMs, 2);
      expect(hops[0].timedOut, isFalse);

      expect(hops[1].hopNumber, 2);
      expect(hops[1].timedOut, isTrue);
      expect(hops[1].rttMs, isNull);

      expect(hops[2].address, '10.0.0.1');
      expect(hops[2].rttMs, 10);

      expect(hops[3].address, '104.16.132.229');
      expect(hops[3].rttMs, 43);
    });

    test('parses an IPv6 hop address (target resolved over IPv6)', () {
      const output = '''
Tracing route to speed.cloudflare.com [2606:4700:7::da]
over a maximum of 10 hops:

  1    11 ms    12 ms   150 ms  2407:d000:2a:0:bdaf:5e57:d165:b469
  8    10 ms    13 ms    10 ms  2606:4700:7::da

Trace complete.
''';
      final hops = parseTracertOutput(output);
      expect(hops.length, 2);
      expect(hops[0].address, '2407:d000:2a:0:bdaf:5e57:d165:b469');
      expect(hops[0].rttMs, 11);
      expect(hops[1].address, '2606:4700:7::da');
      expect(hops[1].rttMs, 10);
    });

    test('ignores header/footer lines that are not hop rows', () {
      const output = '''
Tracing route to example.com [1.2.3.4]
over a maximum of 10 hops:

Trace complete.
''';
      expect(parseTracertOutput(output), isEmpty);
    });
  });

  group('parseTracerouteOutput', () {
    test('parses a single-probe traceroute -n line per hop', () {
      const output = '''
traceroute to speed.cloudflare.com (104.16.132.229), 15 hops max, 60 byte packets
 1  192.168.1.1  2.123 ms
 2  *
 3  10.0.0.1  11.456 ms
 4  104.16.132.229  43.789 ms
''';
      final hops = parseTracerouteOutput(output);
      expect(hops.length, 4);

      expect(hops[0].hopNumber, 1);
      expect(hops[0].address, '192.168.1.1');
      expect(hops[0].rttMs, 2);

      expect(hops[1].hopNumber, 2);
      expect(hops[1].timedOut, isTrue);

      expect(hops[2].address, '10.0.0.1');
      expect(hops[2].rttMs, 11);

      expect(hops[3].address, '104.16.132.229');
      expect(hops[3].rttMs, 44);
    });
  });
}
