Here is a flow of how to generate the test credentials:

```
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Create CA Key

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ openssl genrsa -out CA.key 2048

Generating RSA private key, 2048 bit long modulus
..............+++
..............+++
e is 65537 (0x10001)
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Create CA

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ openssl req -x509 -sha256 -new -nodes -key CA.key -days 3650 -out CACert.pem

You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) []:US
State or Province Name (full name) []:
Locality Name (eg, city) []:
Organization Name (eg, company) []:
Organizational Unit Name (eg, section) []:
Common Name (eg, fully qualified host name) []:
Email Address []:
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Create key for intermediate CA

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ openssl genrsa -out intermediateCA.key 2048

Generating RSA private key, 2048 bit long modulus
.......................................................................................................................+++
....+++
e is 65537 (0x10001)
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Create new CSR for intermediate CA

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ openssl req -new -key intermediateCA.key -subj "/CN=intermediateCA" -out intermediateCA.csr -reqexts v3_req -config opensslcnf.txt

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ openssl x509 -req -days 3650 -in intermediateCA.csr -CA CACert.pem -CAkey CA.key -CAcreateserial -out intermediateCA.pem -extensions v3_req -extfile opensslcnf.txt
Signature ok
subject=/CN=intermediateCA
Getting CA Private Key
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Put in base64 output of the intermediate CA followed by the CA in quotes, comma delimited into a file called "x5c" (removing the prefix and suffix lines of BEGIN/END CERTIFICATE file, and putting it all on 1 line)

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ cat intermediateCA.pem >> x5c

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ cat CACert.pem >> x5c

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ vi x5c
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ cat x5c
"MIIC4zCCAcugAwIBAgIJANcFN39T4aT2MA0GCSqGSIb3DQEBBQUAMA0xCzAJBgNVBAYTAlVTMB4XDTIxMDcyMjIwMDcwNVoXDTMxMDcyMDIwMDcwNVowGTEXMBUGA1UEAwwOaW50ZXJtZWRpYXRlQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC3u2ZIzhwGJTDgmkJH8i2Giqy1dPHY935pI1Q76MQQjhoPbo14TaC5N8wec+QlNt6gItSFrxVdmbxW9uBj4LC7YHTPBls5vGGtnSA2v72KI8fiNqFSUUaWAJKwLIK/487xaJ8HoCMw5NvJtyV4WMxxUhYDE6bPrMYTZ8q6VQbEAyI4qwnVGGpt8k6fvNNUaibWSuV0yha3OQVGoTCc5ZoZQCp3E4YfQ2BjPF66m0XlolcqgbH/8RXZKurhNQpvpvzLC79E1/UlN7sejMSK3R9mg7OYhxuKqTJ62f4F/QL5jKKhYea8DWXFSE/Exa2HChhUUgCwh7Y41EjJcbH2uPvNAgMBAAGjOjA4MDYGA1UdEQQvMC2GEFRTSTpyZWdpb246ZXUtZGWGGVRTSTpjbHVzdGVyLW5hbWU6dGktdGVzdDEwDQYJKoZIhvcNAQEFBQADggEBAIwsNbFgAth5nxkIxy18aPLmJZt8lLQmpIrDJY+exCQdyUn7U6k33IVL9qvzyHRbx6zj4OYk20FHkHe2tGGdppP+via0eEoBI2lMq4ayNmmE72Yvyf+O+B1tPd5dQdwCqxXw2/touRm8OzBd11N1RowvXIzngaZOCiCY7Sx9bHy0GqjIoPvMfxIeLObez1pXlTCjOyGr+nYoomp0p0QgJfklFFxoGMM0CWdDrpOyqhVTSYD9K+j5OtjNCqaHuMOwVmi7DVvQbvMyfpE1Mfgz8+b6y4c/5Mk6PkSIo35hoJ8DzGdNujxQdhGNjvgDl/aCT/82e5u07XWWg/AcjNtk7rU=","MIICljCCAX4CCQC7521H6gt+VTANBgkqhkiG9w0BAQsFADANMQswCQYDVQQGEwJVUzAeFw0yMTA3MjIyMDA2MjhaFw0zMTA3MjAyMDA2MjhaMA0xCzAJBgNVBAYTAlVTMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsDK8ZeiUZxsKIxmJYzxovbllhiYL7BGSkCSBNiSWY79JNF1RdYF2D5z5p0NKpxldKDPxrPvre4k/3pmTGj9h70vUWEZfqbndkFKfKaBi5MT4YuK2UJ4+4p1jqSSkZTieWnw8JbcU7vUf26DnMklPCrIvdx9dvIsrtpfKDSkhmJSMdIyjCTafnqvcxos2Prmi2FfpqbWyXHqBrTxU2GU7EpaykchO8eNS/qynLHSFPrOWJv61TpNJ77UxAxbwYcK9oYj09Ng0iuqjcLRRv8FuKBMsoEFClYQe0zN7oRuKWZ+mPb+ei/gN4S28psKWwv+J9a2Zz7TpRbxgTGbNH6uIYQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAcBuvPbxC6cKvdrSaXCkq7eJvEt7X1curDhOF3V4n9v2bTII7RPxmX8AO8N4P5rUTvCxTtWV6aaG8YCkYHhRH4aYJMlZwRUqMcw8Euy0EZBczQcWqfFwSnfhBnOstYQDzjQDxl6pl+cGU/M+jxwvBCHGWDuGu2iaZ4KnKLexIJ9FB+U7ot34n/eIjyFP2iuIsMguS1zajyLDCHYVhIhbGkyZy2T4PsZNnmVylxfmjR24Vjua+o0pGdAWZmVmdsOsSGR+g68ElTBxtJOf6WOA2D5ZN41UVyWN+9d1DIHHNtdh4HXtgoG+nh6VOX0SmlOtaWHmabJhvUTTteXhEsskTe"
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Generate good token
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ STATEDIR=. ./gen-jwt.py -aud test -sub test -claims 'region:eu-de|some:claim' intermediateCA.key > testGoodToken

➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ # Generate bad token
➜  gen-test-cred-helpers git:(fix-vault-path-login-test) ✗ STATEDIR=. ./gen-jwt.py -aud test -sub test -claims 'region:us|some:claim' intermediateCA.key > testBadToken
```
