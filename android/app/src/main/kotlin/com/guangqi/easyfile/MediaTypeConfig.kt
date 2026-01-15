package com.guangqi.easyfile

/**
 * MediaStore 扫描器的媒体类型配置
 * 集中管理各种文件类型的 MIME 类型定义，便于维护和扩展
 */
object MediaTypeConfig {
    
    /**
     * 文档类型 MIME
     * 与文件系统扫描的扩展名列表保持一致：pdf, doc, docx, txt, rtf, xls, xlsx, ppt, pptx, odt, ods, odp, csv, md
     */
    val DOCUMENT_MIMES = arrayOf(
        // PDF
        "application/pdf",
        // Word
        "application/msword",                                                                    // .doc
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",              // .docx
        // Excel
        "application/vnd.ms-excel",                                                              // .xls
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",                    // .xlsx
        // PowerPoint
        "application/vnd.ms-powerpoint",                                                         // .ppt
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",            // .pptx
        // Text
        "text/plain",                                                                            // .txt
        "application/rtf",                                                                       // .rtf
        // OpenDocument Format (ODF)
        "application/vnd.oasis.opendocument.text",                                              // .odt
        "application/vnd.oasis.opendocument.spreadsheet",                                       // .ods
        "application/vnd.oasis.opendocument.presentation",                                      // .odp
        // CSV
        "text/csv",                                                                              // .csv
        "application/csv",                                                                       // .csv (alternative)
        // Markdown
        "text/markdown",                                                                         // .md
        "text/x-markdown"                                                                        // .md (alternative)
    )
    
    /**
     * 压缩包类型 MIME
     * 支持常见的压缩格式：zip, rar, 7z, tar, gz, bz2, xz
     * 
     * 注意：由于不同 Android 版本和文件管理器对 MIME 类型的识别不一致，
     * 这里添加了多种可能的 MIME 类型变体以确保兼容性。
     * 包含 octet-stream 是为了捕获那些 MIME 类型未被正确识别的压缩包，
     * 会通过扩展名进行二次过滤以避免误匹配。
     */
    val ARCHIVE_MIMES = arrayOf(
        // ZIP
        "application/zip",
        "application/x-zip-compressed",
        "application/x-zip",
        // RAR
        "application/x-rar-compressed",
        "application/vnd.rar",
        "application/x-rar",           // 添加：某些系统使用此 MIME
        "application/rar",             // 添加：另一种可能的 RAR MIME
        // 7-Zip
        "application/x-7z-compressed",
        "application/x-7z",            // 添加：简化版 MIME
        // TAR
        "application/x-tar",
        // GZIP
        "application/gzip",
        "application/x-gzip",
        // BZIP2
        "application/x-bzip2",
        "application/x-bzip",
        // XZ
        "application/x-xz",
        // 通用二进制（兜底，但会通过扩展名严格过滤）
        "application/octet-stream"
    )
    
    /**
     * 压缩包文件扩展名列表
     * 用于二次验证，确保通过扩展名匹配那些 MIME 类型识别错误的压缩包
     */
    val ARCHIVE_EXTENSIONS = arrayOf(
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "tbz2"
    )
    
    /**
     * APK 类型 MIME
     * Android 安装包
     */
    val APK_MIMES = arrayOf(
        "application/vnd.android.package-archive"
    )
}
