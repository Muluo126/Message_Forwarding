#!/bin/sh
MODDIR=${0%/*}
if [ -f "$MODDIR/disable" ]; then
    exit 0
fi

config_conf="$(cat "$MODDIR/config.conf" | egrep -v '^#')"
work_weixin="$(echo "$config_conf" | egrep '^work_weixin=' | sed -n 's/work_weixin=//g;$p')"
if [ "$work_weixin" != "1" ]; then
    exit 0
fi

if type curl > /dev/null 2>&1; then
    MF_bluetooth="$(echo "$config_conf" | egrep '^MF_bluetooth=' | sed -n 's/MF_bluetooth=//g;$p')"
    if [ "$MF_bluetooth" = "1" ]; then
        bluetooth_on="$(settings get global bluetooth_on)"
        if [ "$bluetooth_on" = "1" ]; then
            exit 0
        fi
    fi

    log_n="$(cat "$MODDIR/log.log" | wc -l)"
    if [ "$log_n" -gt "100" ]; then
        sed -i '1,10d' "$MODDIR/log.log" > /dev/null 2>&1
    fi

    serverchan_switch="$(echo "$config_conf" | egrep '^serverchan_switch=' | sed -n 's/serverchan_switch=//g;$p')"
    serverchan_uid="$(echo "$config_conf" | egrep '^serverchan_uid=' | sed -n 's/serverchan_uid=//g;$p')"
    serverchan_sckey="$(echo "$config_conf" | egrep '^serverchan_sckey=' | sed -n 's/serverchan_sckey=//g;$p')"

    Forwarding() {
        wx_agentid="$(echo "$config_conf" | egrep '^wx_agentid=' | sed -n 's/wx_agentid=//g;$p')"
        wx_token="$(cat "$MODDIR/wx_$wx_agentid")"
        wx_url="https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=$wx_token"
        time_wx="$(cat "$MODDIR/time_wx")"
        if [ "$time_wx" = "$(date +%m)" ]; then
            wx_post="{\"touser\": \"@all\",\"agentid\": \"$wx_agentid\",\"msgtype\": \"text\",\"text\": {\"content\": \"$wx_text\"}}"
        else
            wx_post="{\"touser\": \"@all\",\"agentid\": \"$wx_agentid\",\"msgtype\": \"text\",\"text\": {\"content\": \"$wx_text\n\n【通知转发】\"}}"
        fi
        wx_push="$(curl -s --connect-timeout 12 -m 15 -d "$wx_post" "$wx_url")"
        if [ -n "$wx_push" ]; then
            wx_push_errcode="$(echo "$wx_push" | egrep '\"errcode\"' | sed -n 's/ //g;s/.*\"errcode\"://g;s/\".*//g;s/,.*//g;$p')"
            if [ -n "$wx_agentid" ]; then
                if [ "$wx_push_errcode" = "42001" -o "$wx_push_errcode" = "41001" -o "$wx_push_errcode" = "40014" ]; then
                    wx_corpid="$(echo "$config_conf" | egrep '^wx_corpid=' | sed -n 's/wx_corpid=//g;$p')"
                    wx_secret="$(echo "$config_conf" | egrep '^wx_secret=' | sed -n 's/wx_secret=//g;$p')"
                    wx_access_token="$(curl -s --connect-timeout 12 -m 15 "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=$wx_corpid&corpsecret=$wx_secret")"
                    if [ -n "$wx_access_token" ]; then
                        wx_token_errcode="$(echo "$wx_access_token" | egrep '\"errcode\"' | sed -n 's/ //g;s/.*\"errcode\"://g;s/\".*//g;s/,.*//g;$p')"
                        if [ "$wx_token_errcode" = "0" ]; then
                            wx_token="$(echo "$wx_access_token" | egrep '\"access_token\"' | sed -n 's/ //g;s/.*\"access_token\":\"//g;s/\".*//g;$p')"
                            wx_url="https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=$wx_token"
                            if [ "$time_wx" = "$(date +%m)" ]; then
                                wx_post="{\"touser\": \"@all\",\"agentid\": \"$wx_agentid\",\"msgtype\": \"text\",\"text\": {\"content\": \"$wx_text\"}}"
                            else
                                wx_post="{\"touser\": \"@all\",\"agentid\": \"$wx_agentid\",\"msgtype\": \"text\",\"text\": {\"content\": \"$wx_text\n\n【通知转发】\"}}"
                            fi
                            wx_push="$(curl -s --connect-timeout 12 -m 15 -d "$wx_post" "$wx_url")"
                            if [ -n "$wx_push" ]; then
                                wx_push_errcode="$(echo "$wx_push" | egrep '\"errcode\"' | sed -n 's/ //g;s/.*\"errcode\"://g;s/\".*//g;s/,.*//g;$p')"
                            fi
                        else
                            echo "$(date +%F_%T) 【微信通道 消息转发失败】：请检查配置参数[企业ID]、[应用Secret]是否填写正确且相互匹配，返回提示：$wx_access_token" >> "$MODDIR/log.log"
                        fi
                    else
                        echo "$(date +%F_%T) 【微信通道 消息转发失败】：运营商网络问题或IP遭腾讯拦截，请变更外网IP后再尝试。【消息】：$wx_text" >> "$MODDIR/log.log"
                    fi
                fi
            else
                echo "$(date +%F_%T) 【微信通道 消息转发失败】：[应用AgentId]参数未填写" >> "$MODDIR/log.log"
            fi
        fi
        if [ -n "$wx_push" ]; then
            if [ "$wx_push_errcode" = "0" ]; then
                echo "$(date +%m)" > "$MODDIR/time_wx"
                echo "$wx_token" > "$MODDIR/wx_$wx_agentid"
                echo "$(date +%F_%T) 微信通道 消息转发成功：$wx_text" >> "$MODDIR/log.log"
            elif [ "$wx_push_errcode" = "44004" ]; then
                echo "$(date +%F_%T) 【微信通道 消息转发失败】：content错误" >> "$MODDIR/log.log"
            elif [ "$wx_push_errcode" = "60020" ]; then
                echo "$(date +%F_%T) 【微信通道 消息转发失败】：通道有IP限制的新规则，企业微信后台找到[应用管理]-[自建]-应用详情页-企业可信IP，把你设备的外网IP加上去，若设备不是固定IP，那只能用代理IP解决，暂时没有更好的办法，建议使用钉钉通道。返回提示：$wx_push。" >> "$MODDIR/log.log"
            elif [ "$wx_push_errcode" = "45009" ]; then
                echo "$(date +%F_%T) 【微信通道 消息转发失败】：接口调用超过限制，请变更外网IP后再尝试。" >> "$MODDIR/log.log"
            elif [ "$wx_push_errcode" != "42001" -a "$wx_push_errcode" != "41001" -a "$wx_push_errcode" != "40014" ]; then
                echo "$(date +%F_%T) 【微信通道 消息转发失败】：请检查配置参数[企业ID]、[应用Secret]、[应用AgentId]是否填写正确且相互匹配，返回提示：$wx_push" >> "$MODDIR/log.log"
            fi
        else
            echo "$(date +%F_%T) 【微信通道 消息转发失败】：运营商网络问题，访问接口失败，请变更外网IP后再尝试。【消息】：$wx_text" >> "$MODDIR/log.log"
        fi
    }

    dingtalk_push() {
        dd_url="$(echo "$config_conf" | egrep '^dd_Webhook=' | sed -n 's/dd_Webhook=//g;$p')"
        dd_post="{\"msgtype\": \"markdown\",\"markdown\": {\"title\":\"$wx_text\",\"text\": \"$wx_text\n\n【通知转发】\"}}"
        dd_push="$(curl -s --connect-timeout 12 -m 15 -H 'Content-Type: application/json' -d "$dd_post" "$dd_url")"
        if [ -n "$dd_push" ]; then
            dd_push_errcode="$(echo "$dd_push" | egrep '\"errcode\"' | sed -n 's/ //g;s/.*\"errcode\"://g;s/\".*//g;s/,.*//g;$p')"
            if [ "$dd_push_errcode" = "0" ]; then
                echo "$(date +%F_%T) 钉钉通道 消息转发成功：$wx_text" >> "$MODDIR/log.log"
            elif [ "$dd_push_errcode" = "40035" ]; then
                echo "$(date +%F_%T) 【钉钉通道 消息转发失败】：消息内容导致json格式错误，返回提示：$dd_push，请联系作者修复。【消息】：$wx_text" >> "$MODDIR/log.log"
            elif [ "$dd_push_errcode" = "310000" ]; then
                echo "$(date +%F_%T) 【钉钉通道 消息转发失败】：请检查钉钉群机器人-安全设置是否已经且仅设置自定义关键词：通知转发，返回提示：$dd_push。【消息】：$wx_text" >> "$MODDIR/log.log"
            else
                echo "$(date +%F_%T) 【钉钉通道 消息转发失败】：请检查配置参数[dd_Webhook]是否填写正确，返回提示：$dd_push。【消息】：$wx_text" >> "$MODDIR/log.log"
            fi
        else
            echo "$(date +%F_%T) 【钉钉通道 消息转发失败】：运营商网络问题，访问接口失败，请变更外网IP后再尝试。或是请检查配置参数[dd_Webhook]是否填写正确，返回提示：$dd_push。【消息】：$wx_text" >> "$MODDIR/log.log"
        fi
    }

    urlencode() {
        echo "$1" | sed -e 's/ /%20/g' -e ':a;N;$!ba;s/\n/%0A/g'
    }

    # 新增调用新API接口的 Server酱推送函数
    new_serverchan_push() {
        sc_title="通知转发"
        sc_desp="$wx_text"

        sc_url="https://${serverchan_uid}.push.ft07.com/send/${serverchan_sckey}.send"
        sc_post="title=$(urlencode "$sc_title")&desp=$(urlencode "$sc_desp")"

        sc_push="$(curl -s --connect-timeout 12 -m 15 -d "$sc_post" "$sc_url")"
        if echo "$sc_push" | grep -q '"code":0'; then
            echo "$(date +%F_%T) 新Server酱通道 消息转发成功：$wx_text" >> "$MODDIR/log.log"
        else
            echo "$(date +%F_%T) 【新Server酱通道 消息转发失败】：返回内容 $sc_push，【消息】：$wx_text" >> "$MODDIR/log.log"
        fi
    }

    wx_switch="$(echo "$config_conf" | egrep '^wx_switch=' | sed -n 's/wx_switch=//g;$p')"
    dd_switch="$(echo "$config_conf" | egrep '^dd_switch=' | sed -n 's/dd_switch=//g;$p')"
    battery_level="$(dumpsys battery | egrep 'level:' | sed -n 's/.*level: //g;$p')"
    Low_battery="$(echo "$config_conf" | egrep '^Low_battery=' | sed -n 's/Low_battery=//g;$p')"
    if [ -n "$battery_level" -a "$battery_level" -le "$Low_battery" ]; then
        if [ ! -f "$MODDIR/Low_battery" ]; then
            wx_text="低电量提醒：电量$battery_level"
            if [ "$wx_switch" != "0" ]; then
                Forwarding
            fi
            if [ "$dd_switch" = "1" ]; then
                dingtalk_push
            fi
            if [ "$serverchan_switch" = "1" ]; then
                new_serverchan_push
            fi
            touch "$MODDIR/Low_battery" > /dev/null 2>&1
        fi
    fi
    if [ "$battery_level" -gt "$Low_battery" ]; then
        if [ -f "$MODDIR/Low_battery" ]; then
            rm -f "$MODDIR/Low_battery" > /dev/null 2>&1
        fi
    fi
    app_list="$(echo "$config_conf" | egrep '^app=' | sed -n 's/app=//g;s/ //g;$p')"
    if [ ! -n "$app_list" ]; then
        exit 0
    fi
    MF_notification="$(dumpsys notification --noredact | sed -n 's/\\//g;p')"
    if [ ! -n "$MF_notification" ]; then
        MF_notification="$(dumpsys notification | sed -n 's/\\//g;p')"
        if [ ! -n "$MF_notification" ]; then
            exit 0
        fi
    fi
    MF_NotificationRecord="$(echo -e $MF_notification | sed -n 's/NotificationRecord(/\\nNotificationRecord(/g;p')"
    MF_Message="$(echo -e "$MF_NotificationRecord" | sed -n 's/mAdjustments=\[.*//g;s/stats=SingleNotificationStats{.*//g;p')"
    Message_list="$(echo "$MF_Message" | egrep 'NotificationRecord\(' | egrep "$app_list")"
    if [ ! -n "$Message_list" ]; then
        if [ -f "$MODDIR/pushed" ]; then
            rm -f "$MODDIR/pushed" > /dev/null 2>&1
        fi
        exit 0
    fi
    black_list="$(echo -E "$config_conf" | egrep '^black_list=' | sed -n 's/black_list=//g;$p')"
    white_list="$(echo -E "$config_conf" | egrep '^white_list=' | sed -n 's/white_list=//g;$p')"
    Message_n="$(echo "$Message_list" | wc -l)"
    MF_pushed="$(cat "$MODDIR/pushed")"
    display_format="$(echo "$config_conf" | egrep '^display_format=' | sed -n 's/display_format=//g;$p')"
    until [ "$Message_n" = "0" ] ; do
        Message_p="$(echo "$Message_list" | sed -n "${Message_n}p")"
        Message_id="$(echo "$Message_p" | cut -d ' ' -f '1-2' | sed -n 's/NotificationRecord(//g;$p')"
        MF_app="$(echo "$Message_id" | sed -n 's/.* pkg=//g;s/ .*//g;$p')"
        original_pkg="$MF_app"
        Message_app="$(echo "$config_conf" | egrep "^$original_pkg=" | sed -n 's/.*=//g;$p')"
        if [ -n "$Message_app" ]; then
            MF_app="$Message_app"
        fi
        if [ -n "$(echo "$app_list" | egrep "$original_pkg")" -a ! -n "$(echo "$MF_pushed" | egrep "$Message_id")" ]; then
            ticker_Text="$(echo "$Message_p" | egrep 'tickerText=' | sed -n 's/.*tickerText=//g;s/ contentView=.*//g;s/\"/\\\"/g;$p')"
            android_title="$(echo "$Message_p" | egrep 'android\.title=' | sed -n 's/.*android\.title=//g;s/) android\..*//g;s/) isVideoCall=.*//g;s/.*String (//g;s/\"/\\\"/g;$p')"
            if [ -n "$ticker_Text" -a "$ticker_Text" != "null" -a ! -n "$(echo "$android_title" | egrep "$ticker_Text")" ]; then
                if [ -n "$black_list" ]; then
                    ticker_Text="$(echo "$ticker_Text" | egrep -v "$black_list")"
                fi
                if [ -n "$white_list" ]; then
                    ticker_Text="$(echo "$ticker_Text" | egrep "$white_list")"
                fi
                if [ -n "$ticker_Text" ]; then
                    if [ "$display_format" = "2" ]; then
                        wx_text="【$MF_app】\n$(echo "$ticker_Text" | sed 's/vis=0//g')"
                    else
                        wx_text="$(echo "$ticker_Text" | sed 's/vis=0//g')\n【$MF_app】"
                    fi
                fi
            else
                android_text="$(echo "$Message_p" | egrep 'android\.text=' | sed -n 's/.*android\.text=//g;s/) android\..*//g;s/.*String (//g;s/\"/\\\"/g;$p')"
                ticker_Text="$android_title: $android_text"
                if [ -n "$android_title" -o -n "$android_text" ]; then
                    if [ -n "$black_list" ]; then
                        ticker_Text="$(echo "$ticker_Text" | egrep -v "$black_list")"
                    fi
                    if [ -n "$white_list" ]; then
                        ticker_Text="$(echo "$ticker_Text" | egrep "$white_list")"
                    fi
                    ticker_Text="$(echo "$ticker_Text" | egrep -v '”正在运行: ')"
                    if [ -n "$ticker_Text" ]; then
                        if [ "$display_format" = "2" ]; then
                            wx_text="【$MF_app】\n$(echo "$ticker_Text" | sed 's/vis=0//g')"
                        else
                            wx_text="$(echo "$ticker_Text" | sed 's/vis=0//g')\n【$MF_app】"
                        fi
                    fi
                fi
            fi

            # 微信来源信息处理
            if [ "$original_pkg" = "com.tencent.mm" ]; then
                if [ -n "$android_title" ]; then
                    source_info="$android_title"
                else
                    source_info=$(echo "$ticker_Text" | awk -F ':' '{print \$1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                fi
                if [ -n "$source_info" ]; then
                    wx_text="【$MF_app】$source_info\n$(echo "$ticker_Text" | sed 's/vis=0//g')"
                fi
            fi

            if [ -n "$wx_text" ]; then
                if [ "$wx_switch" != "0" ]; then
                    Forwarding
                fi
                if [ "$dd_switch" = "1" ]; then
                    dingtalk_push
                fi
                if [ "$serverchan_switch" = "1" ]; then
                    new_serverchan_push
                fi
            fi
        fi
        Message_n="$(( $Message_n - 1 ))"
    done
    pushed_list="$(echo "$Message_list" | cut -d ' ' -f '1-2' | sed -n 's/NotificationRecord(//g;p')"
    pushed_cat="$(cat "$MODDIR/pushed")"
    if [ "$pushed_list" != "$pushed_cat" ]; then
        echo "$pushed_list" > "$MODDIR/pushed"
    fi
else
    echo "$(date +%F_%T) 系统缺少curl命令模块：无法转发消息，请安装curl模块后再使用" > "$MODDIR/log.log"
fi
#version=2025052600
