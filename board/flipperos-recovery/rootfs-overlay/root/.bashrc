# Recovery banner for interactive shells (covers SSH non-login shells).
if [ -z "${RECOVERY_BANNER_SHOWN:-}" ] && [ -x /usr/bin/recovery-banner ]; then
	/usr/bin/recovery-banner
	RECOVERY_BANNER_SHOWN=1
fi
