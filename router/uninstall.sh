#!/bin/sh
/etc/init.d/pulse stop 2>/dev/null; /etc/init.d/pulse disable 2>/dev/null
rm -rf /www/pulse /www/cgi-bin/pulse /usr/share/pulse /etc/init.d/pulse
echo "已卸载（保留 /etc/config/pulse，如不需要请手动删除）"
