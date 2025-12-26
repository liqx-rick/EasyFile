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
     * 支持常见的压缩格式：zip, rar, 7z, tar, gz, bz2
     */
    val ARCHIVE_MIMES = arrayOf(
        // ZIP
        "application/zip",
        "application/x-zip-compressed",
        // RAR
        "application/x-rar-compressed",
        "application/vnd.rar",
        // 7-Zip
        "application/x-7z-compressed",
        // TAR
        "application/x-tar",
        // GZIP
        "application/gzip",
        "application/x-gzip",
        // BZIP2
        "application/x-bzip2",
        "application/x-bzip",
        // XZ
        "application/x-xz"
    )
    
    /**
     * APK 类型 MIME
     * Android 安装包
     */
    val APK_MIMES = arrayOf(
        "application/vnd.android.package-archive"
    )
}
