package com.guangqi.easyfile

import android.util.Log

/**
 * 统一日志工具类
 * 支持 Flutter 端控制的日志级别
 * 
 * 使用方式：
 * - LogHelper.d(TAG, "debug message")
 * - LogHelper.i(TAG, "info message")
 * - LogHelper.w(TAG, "warning message")
 * - LogHelper.e(TAG, "error message")
 */
object LogHelper {
    
    /**
     * 日志级别枚举（与 Flutter 端保持一致）
     */
    enum class Level(val priority: Int) {
        DEBUG(0),
        INFO(1),
        WARN(2),
        ERROR(3),
        OFF(4);
        
        companion object {
            fun fromString(level: String): Level {
                return when (level.lowercase()) {
                    "debug" -> DEBUG
                    "info" -> INFO
                    "warn" -> WARN
                    "error" -> ERROR
                    "off" -> OFF
                    else -> INFO  // 默认 INFO
                }
            }
        }
    }
    
    /**
     * 当前日志级别（默认 INFO）
     * 可通过 setLevel() 动态修改
     */
    @Volatile
    private var currentLevel: Level = Level.INFO
    
    /**
     * 是否启用日志（方便完全关闭）
     */
    @Volatile
    private var enabled: Boolean = true
    
    /**
     * 设置日志级别
     * 通常由 Flutter 端通过 MethodChannel 调用
     */
    fun setLevel(level: Level) {
        currentLevel = level
        Log.i("LogHelper", "日志级别已设置为: ${level.name}")
    }
    
    /**
     * 通过字符串设置日志级别（方便 MethodChannel 调用）
     */
    fun setLevel(levelString: String) {
        setLevel(Level.fromString(levelString))
    }
    
    /**
     * 启用/禁用日志
     */
    fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
        Log.i("LogHelper", "日志输出已${if (enabled) "启用" else "禁用"}")
    }
    
    /**
     * 获取当前日志级别
     */
    fun getLevel(): Level = currentLevel
    
    /**
     * 检查指定级别的日志是否应该输出
     */
    private fun shouldLog(level: Level): Boolean {
        return enabled && level.priority >= currentLevel.priority
    }
    
    /**
     * DEBUG 级别日志
     */
    fun d(tag: String, message: String) {
        if (shouldLog(Level.DEBUG)) {
            Log.d(tag, message)
        }
    }
    
    /**
     * INFO 级别日志
     */
    fun i(tag: String, message: String) {
        if (shouldLog(Level.INFO)) {
            Log.i(tag, message)
        }
    }
    
    /**
     * WARN 级别日志
     */
    fun w(tag: String, message: String) {
        if (shouldLog(Level.WARN)) {
            Log.w(tag, message)
        }
    }
    
    /**
     * ERROR 级别日志
     */
    fun e(tag: String, message: String, throwable: Throwable? = null) {
        if (shouldLog(Level.ERROR)) {
            if (throwable != null) {
                Log.e(tag, message, throwable)
            } else {
                Log.e(tag, message)
            }
        }
    }
    
    /**
     * 格式化日志（带时间戳）
     */
    fun format(tag: String, level: String, message: String): String {
        val timestamp = System.currentTimeMillis()
        return "[$timestamp] [$level] [$tag] $message"
    }
}
