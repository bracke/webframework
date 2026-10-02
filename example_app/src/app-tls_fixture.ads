--  App.Tls_Fixture -- a committed, self-signed test certificate for the
--  in-process TLS mail catcher and the notifications TLS client. This is the
--  same fixture ssllib ships for its own examples: a self-signed Ed25519
--  certificate for www.example.com / *.example.com, valid for a century, whose
--  only job is to let a real TLS 1.3 handshake complete over the loopback in a
--  test. It is not a credential for anything real and grants no trust beyond
--  this demo. The catcher loads it as its server credential; the smtplib client
--  trusts it (written out with Write_Certificate) and verifies the handshake
--  against Server_Name.
package App.Tls_Fixture is

   --  The reference identity the certificate carries; the TLS client must verify
   --  against this name, so it is also the SMTP host the client is pointed at.
   Server_Name : constant String := "www.example.com";

   --  The self-signed certificate (PEM) -- server credential and client anchor.
   Certificate_PEM : constant String :=
     "-----BEGIN CERTIFICATE-----" & ASCII.LF
     & "MIIBpzCCAVmgAwIBAgIUIBiL9TITIQVBhzTergGMWKLOiR8wBQYDK2VwMBoxGDAW" & ASCII.LF
     & "BgNVBAMMD3d3dy5leGFtcGxlLmNvbTAgFw0yNjA3MzAxODAzNTNaGA8yMTI2MDcw" & ASCII.LF
     & "NjE4MDM1M1owGjEYMBYGA1UEAwwPd3d3LmV4YW1wbGUuY29tMCowBQYDK2VwAyEA" & ASCII.LF
     & "tSCd/v8oVcfUyKtkpjhvvKihzuTaZuuGMuxvHe16teijga4wgaswHQYDVR0OBBYE" & ASCII.LF
     & "FJ3vYTfuje2D1uR+srJJDxMzWjFnMB8GA1UdIwQYMBaAFJ3vYTfuje2D1uR+srJJ" & ASCII.LF
     & "DxMzWjFnMA8GA1UdEwEB/wQFMAMBAf8wKQYDVR0RBCIwIIIPd3d3LmV4YW1wbGUu" & ASCII.LF
     & "Y29tgg0qLmV4YW1wbGUuY29tMA4GA1UdDwEB/wQEAwIHgDAdBgNVHSUEFjAUBggr" & ASCII.LF
     & "BgEFBQcDAQYIKwYBBQUHAwIwBQYDK2VwA0EAHzRbOWV27EsELzrT34OJVQ8xp6d2" & ASCII.LF
     & "B/ju8j65rM9QKEsLYh0n6XDJFLIpg1OfVnAeKVMYbw5KVF8YP4zWpqWKBw==" & ASCII.LF
     & "-----END CERTIFICATE-----" & ASCII.LF;

   --  The matching Ed25519 private key (PEM) -- the catcher's server key.
   Private_Key_PEM : constant String :=
     "-----BEGIN PRIVATE KEY-----" & ASCII.LF
     & "MC4CAQAwBQYDK2VwBCIEINf8wh6nGfnaz8ID+vfApw5tmfpK+UYqxMANsWgMuY++" & ASCII.LF
     & "-----END PRIVATE KEY-----" & ASCII.LF;

   --  Write the certificate PEM to Path so the smtplib TLS client can trust it
   --  as a custom anchor file. Ok is False on any I/O failure.
   procedure Write_Certificate (Path : String; Ok : out Boolean);

end App.Tls_Fixture;
