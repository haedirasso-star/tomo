# Tomo — من TO

منصة فيديو قصير اجتماعية مستقلة تماماً — خادم Supabase خاص · ملفات على Cloudflare R2 · نطاق خاص.
الاسم التجاري يتغيّر من مكان واحد: `APP_NAME` وقت البناء + `APP_ID` في Bootstrap + `site/_make.py`.

## الأقسام
- **الرئيسية**: «لك» (خوارزمية التفاعل والحداثة + فيديو ممول في الموضع الخامس) و«أتابعهم»
- **الأصدقاء** · **✚ نشر** (رفع مباشر إلى R2 بنسبة تقدّم + ضغط تلقائي 720p) · **صندوق الوارد** (نشاط + محادثات فورية) · **الملف الشخصي**
- **الترويج** (من نظام إعلانات TOTV): روّج تحت فيديوهاتك ⇐ ميزانية وهدف ⇐ دفع بوصل ⇐ مراجعة ⇐ أرقام يومية دقيقة + وصل رسمي TO-P-xxxxxx
- **لوحة الإدارة** داخل التطبيق: الترويج · البلاغات · الأسعار وطرق الدفع

## الأمان (للمراجعة في المتاجر)
- صلاحيات RLS على كل جدول — لا مستخدم يرى بيانات غيره الخاصة أو يغيّر العدّادات أو دوره
- الفيديوهات تُنشأ من الخادم فقط بعد التحقق من الملف · المفاتيح السرية في دالة api فقط
- حدود سرعة في الخادم (تعليقات · رسائل · متابعات · بلاغات · نشر) + حدود Supabase Auth ضد التخمين
- كلمة مرور 8+ بحروف وأرقام · جلسة مشفّرة (Keychain/Keystore) · PKCE · لا نسخ احتياطي للبيانات الحساسة
- إبلاغ · حظر · حذف حساب كامل (الملفات + البيانات) · عمر 13+ · سجل إجراءات الإدارة
- صفحات عامة في `site/`: الخصوصية · الشروط · الإرشادات · سلامة الأطفال (مطلوبة في غوغل بلي) · حذف الحساب

## الإعداد
### 1) Supabase
أنشئ مشروعاً ⇐ أضف أسرار GitHub: `SUPABASE_ANON_KEY` · `SUPABASE_ACCESS_TOKEN` (الرابط ومعرّف المشروع مضبوطان)
- Authentication ← Providers: Email (Confirm email مفعّل) · Google · Facebook · Apple
- Authentication ← URL Configuration ← Redirect URLs: `app.tomo://login-callback`
- Authentication ← Policies: أقل طول لكلمة المرور 8

### 2) Cloudflare R2
Bucket باسم التطبيق ⇐ Public access عبر نطاق مخصص (مثل `cdn.example.com`) ⇐ API Token بصلاحية Object Read & Write
أسرار GitHub: `R2_ACCOUNT_ID` · `R2_ACCESS_KEY_ID` · `R2_SECRET_ACCESS_KEY` · `R2_BUCKET` · `R2_PUBLIC_URL`

### 3) الضغط التلقائي (اختياري ومجاني)
`ENCODE_SECRET` (أي نص عشوائي طويل) + `GH_ENCODE_TOKEN` (Fine-grained token على هذا المستودع بصلاحية Contents: Read & write)

### 4) التشغيل
Actions ← **Deploy backend** ثم **Bootstrap platforms** ثم **Build Android**
أول مدير: SQL Editor ← `update profiles set role = 'admin' where username = 'اسمك';`
