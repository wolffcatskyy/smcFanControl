#include <assert.h>
#include "../Classes/ReleaseVersion.h"
int main(void) {
    assert(smc_release_is_newer("v2.8.0", "2.7.0") == 1);
    assert(smc_release_is_newer("v2.10.0", "2.9.9") == 1);
    assert(smc_release_is_newer("v2.7.0", "2.7.0-ce") == 0);
    assert(smc_release_is_newer("v2.6.1", "2.7.0") == 0);
    assert(smc_release_is_newer("v2.8.0-beta", "2.7.0") == -1);
    assert(smc_release_is_newer("2.8", "2.7.0") == -1);
    assert(smc_release_is_newer("", "2.7.0") == -1);
    assert(smc_release_is_newer(NULL, "2.7.0") == -1);
    assert(smc_release_is_newer("2.8.0", "invalid") == -1);
    assert(smc_release_is_newer("99999999999999999999999999.0.0", "2.7.0") == -1);
    assert(smc_release_is_newer("2.8.0<script>", "2.7.0") == -1);
    return 0;
}
