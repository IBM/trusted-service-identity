import policy
import threading

### Datastructures ###

class Secret:
    def __init__(self, value, policy):
        self.value = value
        self.policy = policy



class SecretStore:
    secret_dict = None
    lock = None

    def __init__(self):
        self.secret_dict = {}
        self.lock = threading.Lock()

    def addSecret (self, key, value, claims):
        with self.lock:
            if key not in self.secret_dict:
                self.secret_dict[key] = []

            self.secret_dict[key].append(Secret(value, policy.ClaimsPolicy(claims)))
            return True

    def getSecret (self, key, claims):
        with self.lock:
            if key not in self.secret_dict:
                return None

            for secret in reversed(self.secret_dict[key]):
                if secret.policy.check(claims):
                    return secret.value

            return None

