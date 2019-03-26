#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM jdsieci/php-fpm:5.3.29-minimal

RUN apk add --no-cache --virtual .persistent-deps \
		bzip2

RUN apk add --no-cache --virtual .build-deps \
		freetype-dev \
		libmcrypt-dev \
		libpng-dev \
		libjpeg-turbo-dev \
		libxpm-dev \
		libldap \
		libbz2 \
		gmp-dev \
		bzip2-dev \
		libxml2-dev \
		gettext-dev \
		postgresql-dev \
		recode-dev \
		enchant-dev \
		icu-dev \
	&& docker-php-ext-install iconv mcrypt \
		exif bz2 gmp bcmath soap gettext \
		pgsql pdo_pgsql recode dba calendar \
		intl enchant zip\
	&& docker-php-ext-configure gd --enable-gd-native-ttf --with-freetype-dir=/usr/include/ \
		--with-png-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
		--with-xpm-dir=/usr/include \
	&& docker-php-ext-install gd \
	&& docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd \
	&& docker-php-ext-install pdo_mysql \
	&& docker-php-ext-configure mysqli --with-mysqli=shared,mysqlnd \
	&& docker-php-ext-install mysqli \
	&& docker-php-ext-configure mysql --with-mysql=shared,mysqlnd \
	&& docker-php-ext-install mysql \
	&& runDeps="$( \
		scanelf --needed --nobanner --recursive /usr/local \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)" \
   	&& apk add --no-cache --virtual .php-rundeps $runDeps \
	\
	&& apk del .build-deps \
