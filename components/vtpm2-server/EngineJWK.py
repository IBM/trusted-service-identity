from jwcrypto import jwk
##
# Engine keys only work with the openssl backend
##
from cryptography.hazmat.backends.openssl import rsa
from cryptography.hazmat.backends.openssl import backend

class EngineJWK(jwk.JWK):
    def _get_private_key(self, arg=None):
        return self._engine_priv

    def _get_public_key(self, arg=None):
        return self._engine_pub

    def __init__(self, engine, arg):
        super(EngineJWK, self).__init__()
        backend._lib.ENGINE_load_builtin_engines()
        e = backend._lib.ENGINE_by_id(engine)
        backend.openssl_assert(e != backend._ffi.NULL)
        res = backend._lib.ENGINE_init(e)
        backend.openssl_assert(res == 1)
        evp_pkey = backend._lib.ENGINE_load_private_key(e, arg, backend._ffi.NULL, backend._ffi.NULL)
        backend._lib.ENGINE_finish(e)
        backend.openssl_assert(evp_pkey != backend._ffi.NULL)
        key_type = backend._lib.EVP_PKEY_id(evp_pkey)
        if key_type == backend._lib.EVP_PKEY_RSA:
            rsakey = backend._lib.EVP_PKEY_get1_RSA(evp_pkey)
            self._engine_priv = rsa._RSAPrivateKey(backend, rsakey, evp_pkey)
            self._engine_pub = rsa._RSAPublicKey(backend, rsakey, evp_pkey)
            self._import_pyca_pub_rsa(self._engine_pub)
        else:
            raise jwk.InvalidJWKValue('Unknown Engine Key type')
        return

