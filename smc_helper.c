#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <IOKit/IOKitLib.h>

#define kSMCCall 2
#define kSMCReadKey  5
#define kSMCWriteKey 6
#define kSMCGetKeyInfo 9

typedef struct {
    unsigned char major;
    unsigned char minor;
    unsigned char build;
    unsigned char reserved[1];
    unsigned short release;
} SMCKeyData_vers_t;

typedef struct {
    unsigned short version;
    unsigned short length;
    unsigned int cpuPLimit;
    unsigned int gpuPLimit;
    unsigned int memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    unsigned int dataSize;
    unsigned int dataType;
    unsigned char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef unsigned char SMCBytes_t[32];

typedef struct {
    unsigned int key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    unsigned char result;
    unsigned char status;
    unsigned char data8;
    unsigned int data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

unsigned int string_to_key(const char *str) {
    unsigned int key = 0;
    for (int i = 0; i < 4; i++) {
        if (str[i] == '\0') break;
        key = (key << 8) + (unsigned char)str[i];
    }
    return key;
}

void key_to_string(unsigned int key, char *str) {
    str[0] = (key >> 24) & 0xFF;
    str[1] = (key >> 16) & 0xFF;
    str[2] = (key >> 8) & 0xFF;
    str[3] = key & 0xFF;
    str[4] = '\0';
}

kern_return_t smc_call(io_connect_t conn, int cmd, SMCKeyData_t *input, SMCKeyData_t *output) {
    input->data8 = cmd;
    size_t in_size = sizeof(SMCKeyData_t);
    size_t out_size = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, kSMCCall, input, in_size, output, &out_size);
}

// Low-level read key
kern_return_t smc_read(io_connect_t conn, const char *key_str, SMCKeyData_t *val_output) {
    SMCKeyData_t info_input;
    SMCKeyData_t info_output;
    memset(&info_input, 0, sizeof(SMCKeyData_t));
    info_input.key = string_to_key(key_str);
    
    kern_return_t kr = smc_call(conn, kSMCGetKeyInfo, &info_input, &info_output);
    if (kr != kIOReturnSuccess) return kr;
    
    SMCKeyData_t val_input;
    memset(&val_input, 0, sizeof(SMCKeyData_t));
    val_input.key = string_to_key(key_str);
    val_input.keyInfo.dataSize = info_output.keyInfo.dataSize;
    
    return smc_call(conn, kSMCReadKey, &val_input, val_output);
}

// Low-level write key
kern_return_t smc_write(io_connect_t conn, const char *key_str, unsigned char *bytes, int size) {
    SMCKeyData_t info_input;
    SMCKeyData_t info_output;
    memset(&info_input, 0, sizeof(SMCKeyData_t));
    info_input.key = string_to_key(key_str);
    
    kern_return_t kr = smc_call(conn, kSMCGetKeyInfo, &info_input, &info_output);
    if (kr != kIOReturnSuccess) return kr;
    
    SMCKeyData_t write_input;
    SMCKeyData_t write_output;
    memset(&write_input, 0, sizeof(SMCKeyData_t));
    write_input.key = string_to_key(key_str);
    write_input.keyInfo.dataSize = size;
    memcpy(write_input.bytes, bytes, size);
    
    return smc_call(conn, kSMCWriteKey, &write_input, &write_output);
}

// Helpers for type conversions
float get_float_val(io_connect_t conn, const char *key_str) {
    SMCKeyData_t output;
    if (smc_read(conn, key_str, &output) == kIOReturnSuccess) {
        float f_val;
        memcpy(&f_val, output.bytes, sizeof(float));
        return f_val;
    }
    return 0.0f;
}

int get_ui8_val(io_connect_t conn, const char *key_str) {
    SMCKeyData_t output;
    if (smc_read(conn, key_str, &output) == kIOReturnSuccess) {
        return output.bytes[0];
    }
    return -1;
}

kern_return_t set_ui8_val(io_connect_t conn, const char *key_str, unsigned char val) {
    return smc_write(conn, key_str, &val, 1);
}

kern_return_t set_float_val(io_connect_t conn, const char *key_str, float val) {
    unsigned char bytes[4];
    memcpy(bytes, &val, sizeof(float));
    return smc_write(conn, key_str, bytes, 4);
}

int main(int argc, char **argv) {
    // Open SMC Connection
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    }
    
    if (service == 0) {
        printf("{\"error\": \"AppleSMC service not found\"}\n");
        return 1;
    }
    
    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    
    if (kr != kIOReturnSuccess) {
        printf("{\"error\": \"Failed to open SMC connection (0x%08x)\"}\n", kr);
        return 1;
    }
    
    if (argc < 2) {
        printf("Usage:\n");
        printf("  %s status           Get JSON info of fans and temperatures\n", argv[0]);
        printf("  %s set <idx> <rpm>  Set fan at index idx to speed in RPM\n", argv[0]);
        printf("  %s auto             Set all fans to automatic mode\n", argv[0]);
        printf("  %s watchdog <pid>   Monitor pid and restore auto mode if pid dies\n", argv[0]);
        IOServiceClose(conn);
        return 0;
    }
    
    if (strcmp(argv[1], "status") == 0) {
        // Read Fan Count
        int fan_count = get_ui8_val(conn, "FNum");
        if (fan_count < 0) fan_count = 0;
        
        // Read CPU Temp (taking maximum of multiple CPU sensors)
        char cpu_keys[][5] = {"Tp01", "Tp05", "Tp09", "Tp0D"};
        float max_cpu = 0.0f;
        for (int i = 0; i < 4; i++) {
            float t = get_float_val(conn, cpu_keys[i]);
            if (t > max_cpu) max_cpu = t;
        }
        
        // Read GPU Temp (TG0D)
        float gpu_temp = get_float_val(conn, "Tg0D");
        if (gpu_temp == 0.0f) {
            gpu_temp = get_float_val(conn, "Tg05"); // Fallback
        }
        
        // Read System Temp
        float sys_temp = get_float_val(conn, "TS0P");
        
        printf("{\n");
        printf("  \"cpu_temp\": %.2f,\n", max_cpu);
        printf("  \"gpu_temp\": %.2f,\n", gpu_temp);
        printf("  \"system_temp\": %.2f,\n", sys_temp);
        printf("  \"fans\": [\n");
        for (int i = 0; i < fan_count; i++) {
            char key_ac[6], key_tg[6], key_mn[6], key_mx[6], key_md[6];
            sprintf(key_ac, "F%dAc", i);
            sprintf(key_tg, "F%dTg", i);
            sprintf(key_mn, "F%dMn", i);
            sprintf(key_mx, "F%dMx", i);
            sprintf(key_md, "F%dMd", i);
            
            float actual = get_float_val(conn, key_ac);
            float target = get_float_val(conn, key_tg);
            float min = get_float_val(conn, key_mn);
            float max = get_float_val(conn, key_mx);
            int mode = get_ui8_val(conn, key_md);
            
            printf("    {\n");
            printf("      \"index\": %d,\n", i);
            printf("      \"actual\": %.2f,\n", actual);
            printf("      \"target\": %.2f,\n", target);
            printf("      \"min\": %.2f,\n", min);
            printf("      \"max\": %.2f,\n", max);
            printf("      \"mode\": \"%s\"\n", mode == 1 ? "manual" : "auto");
            printf("    }%s\n", (i == fan_count - 1) ? "" : ",");
        }
        printf("  ]\n");
        printf("}\n");
    } 
    else if (strcmp(argv[1], "set") == 0) {
        if (argc < 4) {
            printf("{\"error\": \"Missing parameters. Usage: set <idx> <rpm>\"}\n");
            IOServiceClose(conn);
            return 1;
        }
        
        int idx = atoi(argv[2]);
        float rpm = atof(argv[3]);
        
        char key_md[6];
        char key_tg[6];
        sprintf(key_md, "F%dMd", idx);
        sprintf(key_tg, "F%dTg", idx);
        
        // To write target speed we first set manual mode (F{idx}Md = 1)
        kr = set_ui8_val(conn, key_md, 1);
        if (kr != kIOReturnSuccess) {
            printf("{\"error\": \"Failed to write manual mode for fan %d (0x%08x)\"}\n", idx, kr);
            IOServiceClose(conn);
            return 1;
        }
        
        // Write speed target
        kr = set_float_val(conn, key_tg, rpm);
        if (kr != kIOReturnSuccess) {
            printf("{\"error\": \"Failed to write target speed %.2f for fan %d (0x%08x)\"}\n", rpm, idx, kr);
            IOServiceClose(conn);
            return 1;
        }
        
        printf("{\"success\": true, \"message\": \"Fan %d set to %.2f RPM\"}\n", idx, rpm);
    } 
    else if (strcmp(argv[1], "auto") == 0) {
        int fan_count = get_ui8_val(conn, "FNum");
        if (fan_count < 0) fan_count = 0;
        
        int success_count = 0;
        for (int i = 0; i < fan_count; i++) {
            char key_md[6];
            sprintf(key_md, "F%dMd", i);
            kr = set_ui8_val(conn, key_md, 0); // Restore auto
            if (kr == kIOReturnSuccess) {
                success_count++;
            }
        }
        printf("{\"success\": true, \"message\": \"Restored %d/%d fans to auto mode\"}\n", success_count, fan_count);
    } 
    else if (strcmp(argv[1], "watchdog") == 0) {
        if (argc < 3) {
            printf("{\"error\": \"Missing PID parameters. Usage: watchdog <pid>\"}\n");
            IOServiceClose(conn);
            return 1;
        }
        pid_t parent_pid = (pid_t)atoi(argv[2]);
        printf("{\"success\": true, \"message\": \"Watchdog started for PID %d\"}\n", parent_pid);
        fflush(stdout);
        
        while (1) {
            sleep(1);
            if (kill(parent_pid, 0) != 0 && errno == ESRCH) {
                // Parent is dead! Revert to auto
                int fan_count = get_ui8_val(conn, "FNum");
                if (fan_count < 0) fan_count = 0;
                for (int i = 0; i < fan_count; i++) {
                    char key_md[6];
                    sprintf(key_md, "F%dMd", i);
                    set_ui8_val(conn, key_md, 0);
                }
                break;
            }
        }
    }
    else {
        printf("{\"error\": \"Unknown command\"}\n");
    }
    
    IOServiceClose(conn);
    return 0;
}
