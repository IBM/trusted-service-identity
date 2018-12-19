### Datastructures ###
class ClaimsPolicy:
    claims_check = {}

    def __init__(self, claims_check):
        self.claims_check = claims_check.copy()

    def check (self, claims):
        for k, v in self.claims_check.items():
            if k not in claims or str(claims[k]) != str(v):
                return False

        return True
