/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "auth.h"
#include <grp.h>
#include <membership.h>
int ce_authorized_uid(uid_t uid) {
  if (uid == 0)
    return 1;
  struct group *admin = getgrnam("admin");
  if (!admin)
    return 0;
  gid_t group = admin->gr_gid;
  uuid_t user_uuid, group_uuid;
  int member = 0;
  if (mbr_uid_to_uuid(uid, user_uuid) || mbr_gid_to_uuid(group, group_uuid) ||
      mbr_check_membership(user_uuid, group_uuid, &member))
    return 0;
  return member == 1;
}
