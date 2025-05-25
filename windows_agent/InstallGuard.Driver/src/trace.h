/*++

Módulo:

    trace.h

Descripción:

    Declaraciones y definiciones para el subsistema de seguimiento (trace)
    del controlador minifiltro InstallGuard.

--*/

#ifndef _INSTALLGUARD_TRACE_H_
#define _INSTALLGUARD_TRACE_H_

// Control GUID: {A77E18E4-C415-4D8E-B21E-8F2F9858F43A}
#define WPP_CONTROL_GUIDS \
    WPP_DEFINE_CONTROL_GUID( \
        InstallGuardTraceGuid, (A77E18E4,C415,4D8E,B21E,8F2F9858F43A), \
        WPP_DEFINE_BIT(TRACE_INIT)               /* bit  0 = 0x00000001 */ \
        WPP_DEFINE_BIT(TRACE_OPERATION)          /* bit  1 = 0x00000002 */ \
        WPP_DEFINE_BIT(TRACE_FILTER)             /* bit  2 = 0x00000004 */ \
        WPP_DEFINE_BIT(TRACE_COMMUNICATION)      /* bit  3 = 0x00000008 */ \
        WPP_DEFINE_BIT(TRACE_NOTIFICATION)       /* bit  4 = 0x00000010 */ \
        WPP_DEFINE_BIT(TRACE_ERROR)              /* bit  5 = 0x00000020 */ \
        )

// Macros para la generación de trazas
#define WPP_LEVEL_FLAGS_LOGGER(lvl, flags) WPP_LEVEL_LOGGER(flags)
#define WPP_LEVEL_FLAGS_ENABLED(lvl, flags) (WPP_LEVEL_ENABLED(flags) && WPP_CONTROL(WPP_BIT_ ## flags).Level >= lvl)

// Macro para generar trazas de cadenas unicode que contienen % (ejemplo: rutas de archivo)
#define WPP_LEVEL_FLAGS_ENABLED_EX(lvl, flags, formatstring) WPP_LEVEL_FLAGS_ENABLED(lvl, flags)
#define WPP_LEVEL_FLAGS_LOGGER_EX(lvl, flags, formatstring) WPP_LEVEL_FLAGS_LOGGER(lvl, flags)
#define WPP_LEVEL_FLAGS_PRE(lvl, flags, formatstring) { \
    if (WPP_LEVEL_FLAGS_ENABLED_EX(lvl, flags, formatstring)) {
#define WPP_LEVEL_FLAGS_POST(lvl, flags, formatstring) ; } }

// Macros para diferentes niveles de log
#define LOG_INFO(component, format, ...) \
    WPP_LEVEL_FLAGS_PRE(TRACE_LEVEL_INFORMATION, component, format) \
    DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_INFO_LEVEL, format, __VA_ARGS__) \
    WPP_LEVEL_FLAGS_POST(TRACE_LEVEL_INFORMATION, component, format)

#define LOG_WARNING(component, format, ...) \
    WPP_LEVEL_FLAGS_PRE(TRACE_LEVEL_WARNING, component, format) \
    DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_WARNING_LEVEL, format, __VA_ARGS__) \
    WPP_LEVEL_FLAGS_POST(TRACE_LEVEL_WARNING, component, format)

#define LOG_ERROR(component, format, ...) \
    WPP_LEVEL_FLAGS_PRE(TRACE_LEVEL_ERROR, component, format) \
    DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_ERROR_LEVEL, format, __VA_ARGS__) \
    WPP_LEVEL_FLAGS_POST(TRACE_LEVEL_ERROR, component, format)

#endif // _INSTALLGUARD_TRACE_H_ 