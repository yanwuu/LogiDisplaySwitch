#import "NetSync.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <unistd.h>
#import <string.h>

#define UDP_PORT 52417

void broadcastSwitchSignal(const char *signal) {
    if (!signal) return;
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return;

    int broadcastEnable = 1;
    setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));

    size_t len = strlen(signal);

    // 1. 发往通用局域网受限广播 255.255.255.255
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(UDP_PORT);
    addr.sin_addr.s_addr = inet_addr("255.255.255.255");
    sendto(sock, signal, len, 0, (struct sockaddr *)&addr, sizeof(addr));

    // 2. 遍历所有活跃网卡，发往各子网广播地址 (如 192.168.1.255)
    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) == 0) {
        for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
            if (!(ifa->ifa_flags & IFF_UP) || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
            if ((ifa->ifa_flags & IFF_BROADCAST) && ifa->ifa_dstaddr) {
                struct sockaddr_in baddr = *(struct sockaddr_in *)ifa->ifa_dstaddr;
                baddr.sin_port = htons(UDP_PORT);
                sendto(sock, signal, len, 0, (struct sockaddr *)&baddr, sizeof(struct sockaddr_in));
            }
        }
        freeifaddrs(ifaddr);
    }

    close(sock);
}
