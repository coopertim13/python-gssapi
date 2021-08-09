GSSAPI="BASE"  # This ensures that a full module is generated by Cython

import typing

from libc.stdint cimport int32_t, int64_t, uint64_t, uintptr_t, UINT32_MAX
from libc.stdlib cimport calloc, free
from libc.time cimport time_t

from gssapi.raw.creds cimport Creds
from gssapi.raw.cython_converters cimport c_make_oid
from gssapi.raw.cython_types cimport *
from gssapi.raw.sec_contexts cimport SecurityContext

from gssapi.raw import types as gsstypes
from gssapi.raw.named_tuples import CfxKeyData, Rfc1964KeyData

from gssapi.raw.misc import GSSError


cdef extern from "python_gssapi_krb5.h":
    # Heimdal on macOS hides these 3 functions behind a private symbol
    """
    #ifdef OSX_HAS_GSS_FRAMEWORK
    #define gsskrb5_extract_authtime_from_sec_context \
        __ApplePrivate_gsskrb5_extract_authtime_from_sec_context

    #define gss_krb5_import_cred __ApplePrivate_gss_krb5_import_cred

    #define gss_krb5_get_tkt_flags __ApplePrivate_gss_krb5_get_tkt_flags
    #endif
    """

    cdef struct gss_krb5_lucid_key:
        OM_uint32 type
        OM_uint32 length
        void *data
    ctypedef gss_krb5_lucid_key gss_krb5_lucid_key_t

    cdef struct gss_krb5_rfc1964_keydata:
        OM_uint32 sign_alg
        OM_uint32 seal_alg
        gss_krb5_lucid_key_t ctx_key
    ctypedef gss_krb5_rfc1964_keydata gss_krb5_rfc1964_keydata_t

    cdef struct gss_krb5_cfx_keydata:
        OM_uint32 have_acceptor_subkey
        gss_krb5_lucid_key_t ctx_key
        gss_krb5_lucid_key_t acceptor_subkey
    ctypedef gss_krb5_cfx_keydata gss_krb5_cfx_keydata_t

    cdef struct gss_krb5_lucid_context_v1:
        OM_uint32 version
        OM_uint32 initiate
        OM_uint32 endtime
        uint64_t send_seq
        uint64_t recv_seq
        OM_uint32 protocol
        gss_krb5_rfc1964_keydata_t rfc1964_kd
        gss_krb5_cfx_keydata_t cfx_kd
    ctypedef gss_krb5_lucid_context_v1 gss_krb5_lucid_context_v1_t

    gss_OID GSS_KRB5_NT_PRINCIPAL_NAME
    int32_t _PY_GSSAPI_KRB5_TIMESTAMP

    # The krb5 specific types are defined generically as the type names differ
    # across GSSAPI implementations.

    OM_uint32 gss_krb5_ccache_name(OM_uint32 *minor_status, const char *name,
                                   const char **out_name) nogil

    OM_uint32 gss_krb5_export_lucid_sec_context(OM_uint32 *minor_status,
                                                gss_ctx_id_t *context_handle,
                                                OM_uint32 version,
                                                void **kctx) nogil

    # The actual authtime size differs across implementations.  See individual
    # methods for more information.
    OM_uint32 gsskrb5_extract_authtime_from_sec_context(
        OM_uint32 *minor_status, gss_ctx_id_t context_handle,
        void *authtime) nogil

    OM_uint32 gsskrb5_extract_authz_data_from_sec_context(
        OM_uint32 *minor_status, const gss_ctx_id_t context_handle,
        int ad_type, gss_buffer_t ad_data) nogil

    OM_uint32 gss_krb5_free_lucid_sec_context(OM_uint32 *minor_status,
                                              void *kctx) nogil

    OM_uint32 gss_krb5_import_cred(OM_uint32 *minor_status,
                                   void *id,  # krb5_ccache
                                   void *keytab_principal,  # krb5_principal
                                   void *keytab,  # krb5_keytab
                                   gss_cred_id_t *cred) nogil

    # MIT uses a int32_t whereas Heimdal uses uint32_t.  Use void * to satisfy
    # the compiler.
    OM_uint32 gss_krb5_get_tkt_flags(OM_uint32 *minor_status,
                                     gss_ctx_id_t context_handle,
                                     void *ticket_flags) nogil

    OM_uint32 gss_krb5_set_allowable_enctypes(OM_uint32 *minor_status,
                                              gss_cred_id_t cred,
                                              OM_uint32 num_ktypes,
                                              int32_t *ktypes) nogil


cdef class Krb5LucidContext:
    """
    The base container returned by :meth:`krb5_export_lucid_sec_context` when
    an unknown version was requested.
    """
    # defined in pxd
    # cdef void *raw_ctx

    def __cinit__(Krb5LucidContext self):
        self.raw_ctx = NULL

    def __dealloc__(Krb5LucidContext self):
        cdef OM_uint32 min_stat = 0

        if self.raw_ctx:
            gss_krb5_free_lucid_sec_context(&min_stat, self.raw_ctx)
            self.raw_ctx = NULL


cdef class Krb5LucidContextV1(Krb5LucidContext):
    """
    Kerberos context data returned by :meth:`krb5_export_lucid_sec_context`
    when version 1 was requested.
    """

    @property
    def version(self) -> typing.Optional[int]:
        """The structure version number

        Returns:
            Optional[int]: the structure version number
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            return ctx.version

    @property
    def is_initiator(self) -> typing.Optional[bool]:
        """Whether the context was the initiator

        Returns:
            Optional[bool]: ``True`` when the exported context was the
            initiator
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            return ctx.initiate != 0

    @property
    def endtime(self) -> typing.Optional[int]:
        """Expiration time of the context

        Returns:
            Optional[int]: the expiration time of the context
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            return ctx.endtime

    @property
    def send_seq(self) -> typing.Optional[int]:
        """Sender sequence number

        Returns:
            Optional[int]: the sender sequence number
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            return ctx.send_seq

    @property
    def recv_seq(self) -> typing.Optional[int]:
        """Receiver sequence number

        Returns:
            Optional[int]: the receiver sequence number
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            return ctx.recv_seq

    @property
    def protocol(self) -> typing.Optional[int]:
        """The protocol number

        If the protocol number is 0 then :attr:`rfc1964_kd` is set and
        :attr:`cfx_kd` is `None`. If the protocol number is 1 then the opposite
        is true.

        Protocol 0 refers to RFC1964 and 1 refers to RFC4121.

        Returns:
            Optional[int]: the protocol number
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            return ctx.protocol

    @property
    def rfc1964_kd(self) -> typing.Optional[Rfc1964KeyData]:
        """Keydata for protocol 0 (RFC1964)

        This will be set when :attr:`protocol` is ``0``.

        Returns:
            Optional[Rfc1964KeyData]: the RFC1964 key data
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx != NULL and self.protocol == 0:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            kd = ctx.rfc1964_kd
            key = <bytes>(<char *>kd.ctx_key.data)[:kd.ctx_key.length]

            return Rfc1964KeyData(kd.sign_alg, kd.seal_alg, kd.ctx_key.type,
                                  key)

    @property
    def cfx_kd(self) -> typing.Optional[CfxKeyData]:
        """Key data for protocol 1 (RFC4121)

        This will be set when :attr:`protocol` is ``1``.

        Returns:
            Optional[CfxKeyData]: the RFC4121 key data
        """
        cdef gss_krb5_lucid_context_v1_t *ctx = NULL

        if self.raw_ctx != NULL and self.protocol == 1:
            ctx = <gss_krb5_lucid_context_v1_t *>self.raw_ctx
            kd = ctx.cfx_kd
            ctx_type = ctx_key = acceptor_type = acceptor_key = None

            ctx_type = kd.ctx_key.type
            ctx_key = <bytes>(<char *>kd.ctx_key.data)[:kd.ctx_key.length]

            if kd.have_acceptor_subkey != 0:
                acceptor_type = kd.acceptor_subkey.type
                key = kd.acceptor_subkey
                acceptor_key = <bytes>(<char *>key.data)[:key.length]

            return CfxKeyData(ctx_type, ctx_key, acceptor_type,
                              acceptor_key)


# Unfortunately MIT defines it as const - use the cast to silence warnings
gsstypes.NameType.krb5_nt_principal_name = c_make_oid(
    <gss_OID>GSS_KRB5_NT_PRINCIPAL_NAME)


def krb5_ccache_name(const unsigned char[:] name):
    """
    krb5_ccache_name(name)
    Set the default Kerberos Protocol credentials cache name.

    This method sets the default credentials cache name for use by he Kerberos
    mechanism. The default credentials cache is used by
    :meth:`~gssapi.raw.creds.acquire_cred` to create a GSS-API credential. It
    is also used by :meth:`~gssapi.raw.sec_contexts.init_sec_context` when
    `GSS_C_NO_CREDENTIAL` is specified.

    Note:
        Heimdal does not return the old name when called. It also does not
        reset the ccache lookup behaviour when setting to ``None``.

    Note:
        The return value may not be thread safe.

    Args:
        name (Optional[bytes]): the name to set as the new thread specific
            ccache name. Set to ``None`` to revert back to getting the ccache
            from the config/environment settings.

    Returns:
        bytes: the old name that was previously set

    Raises:
        ~gssapi.exceptions.GSSError
    """
    cdef const char *name_ptr = NULL
    if name is not None and len(name):
        name_ptr = <const char*>&name[0]

    cdef const char *old_name_ptr = NULL
    cdef OM_uint32 maj_stat, min_stat
    with nogil:
        maj_stat = gss_krb5_ccache_name(&min_stat, name_ptr, &old_name_ptr)

    if maj_stat == GSS_S_COMPLETE:
        out_name = None
        if old_name_ptr:
            out_name = <bytes>old_name_ptr

        return out_name

    else:
        raise GSSError(maj_stat, min_stat)


def krb5_export_lucid_sec_context(SecurityContext context not None,
                                  OM_uint32 version):
    """
    krb5_export_lucid_sec_context(context, version)
    Retuns a non-opaque version of the internal context info.

    Gets information about the Kerberos security context passed in. Currently
    only version 1 is known and supported by this library.

    Note:
        The context handle must not be used again by the caller after this
        call.

    Args:
        context ((~gssapi.raw.sec_contexts.SecurityContext): the current
            security context
        version (int): the output structure version to export.  Currently
            only 1 is supported.

    Returns:
        Krb5LucidContext: the non-opaque version context info

    Raises:
        ~gssapi.exceptions.GSSError
    """
    info = {
        1: Krb5LucidContextV1,
    }.get(version, Krb5LucidContext)()
    cdef void **raw_ctx = <void **>&(<Krb5LucidContext>info).raw_ctx

    cdef OM_uint32 maj_stat, min_stat
    with nogil:
        maj_stat = gss_krb5_export_lucid_sec_context(&min_stat,
                                                     &context.raw_ctx,
                                                     version, raw_ctx)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)

    return info


def krb5_extract_authtime_from_sec_context(SecurityContext context not None):
    """
    krb5_extract_authtime_from_sec_context(context)
    Get the auth time for the security context.

    Gets the auth time for the established security context.

    Note:
        Heimdal can only get the authtime on the acceptor security context.
        MIT is able to get the authtime on both initiators and acceptors.

    Args:
        context ((~gssapi.raw.sec_contexts.SecurityContext): the current
            security context

    Returns:
        int: the authtime

    Raises:
        ~gssapi.exceptions.GSSError
    """
    # In Heimdal, authtime is time_t which is either a 4 or 8 byte int.  By
    # passing in a uint64_t reference, there should be enough space for GSSAPI
    # to store the data in either situation. Coming back to Python it will be
    # handled as a normal int without loosing data.
    cdef uint64_t time = 0

    cdef OM_uint32 maj_stat, min_stat
    with nogil:
        maj_stat = gsskrb5_extract_authtime_from_sec_context(&min_stat,
                                                             context.raw_ctx,
                                                             <void *>&time)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)

    return time


def krb5_extract_authz_data_from_sec_context(SecurityContext context not None,
                                             ad_type):
    """
    krb5_extract_authz_data_from_sec_context(context, ad_type)
    Extracts Kerberos authorization data.

    Extracts authorization data that may be stored within the context.

    Note:
        Only operates on acceptor contexts.

    Args:
        context ((~gssapi.raw.sec_contexts.SecurityContext): the current
            security context
        ad_type (int): the type of data to extract

    Returns:
        bytes: the raw authz data from the sec context

    Raises:
        ~gssapi.exceptions.GSSError
    """
    # GSS_C_EMPTY_BUFFER
    cdef gss_buffer_desc ad_data = gss_buffer_desc(0, NULL)
    cdef int ad_type_val = <int>ad_type

    cdef OM_uint32 maj_stat, min_stat
    with nogil:
        maj_stat = gsskrb5_extract_authz_data_from_sec_context(&min_stat,
                                                               context.raw_ctx,
                                                               ad_type_val,
                                                               &ad_data)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)

    try:
        return <bytes>(<char *>ad_data.value)[:ad_data.length]

    finally:
        gss_release_buffer(&min_stat, &ad_data)


def krb5_import_cred(Creds cred_handle not None, cache=None,
                     keytab_principal=None, keytab=None):
    """
    krb5_import_cred(cred_handle, cache=None, keytab_principal=None, \
    keytab=None)
    Import Krb5 credentials into GSSAPI credential.

    Imports the krb5 credentials (either or both of the keytab and cache) into
    the GSSAPI credential so it can be used within GSSAPI. The ccache is
    copied by reference and thus shared, so if the credential is destroyed,
    all users of cred_handle will fail.

    Args:
        cred_handle (Creds): the credential handle to import into
        cache (int): the krb5_ccache address pointer, as an int, to import
            from
        keytab_principal (int): the krb5_principal address pointer, as an int,
            of the credential to import
        keytab (int): the krb5_keytab address pointer, as an int, of the
            keytab to import

    Returns:
        None

    Raises:
        ~gssapi.exceptions.GSSError
    """
    cdef void *cache_ptr = NULL
    if cache is not None and cache:
        cache_ptr = <void *>(<uintptr_t>cache)

    cdef void *keytab_princ = NULL
    if keytab_principal is not None and keytab_principal:
        keytab_princ = <void *>(<uintptr_t>keytab_principal)

    cdef void *kt = NULL
    if keytab is not None and keytab:
        kt = <void *>(<uintptr_t>keytab)

    if cache_ptr == NULL and kt == NULL:
        raise ValueError("Either cache or keytab must be set")

    cdef OM_uint32 maj_stat, min_stat
    with nogil:
        maj_stat = gss_krb5_import_cred(&min_stat, cache_ptr, keytab_princ,
                                        kt, &cred_handle.raw_creds)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)


def krb5_get_tkt_flags(SecurityContext context not None):
    """
    krb5_get_tkt_flags(context)
    Return ticket flags for the kerberos ticket.

    Return the ticket flags for the kerberos ticket received when
    authenticating the initiator.

    Note:
        Heimdal can only get the tkt flags on the acceptor security context.
        MIT is able to get the tkt flags on initators and acceptors.

    Args:
        context (~gssapi.raw.sec_contexts.SecurityContext): the security
            context

    Returns:
        int: the ticket flags for the received kerberos ticket

    Raises:
        ~gssapi.exceptions.GSSError
    """
    cdef OM_uint32 maj_stat, min_stat
    cdef uint32_t ticket_flags = 0

    with nogil:
        maj_stat = gss_krb5_get_tkt_flags(&min_stat, context.raw_ctx,
                                          <void *>&ticket_flags)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)

    return ticket_flags


def krb5_set_allowable_enctypes(Creds cred_handle not None,
                                ktypes):
    """
    krb5_set_allowable_enctypes(cred_handle, ktypes)
    Limits the keys that can be exported.

    Called by a context initiator after acquiring the creds but before calling
    :meth:`~gssapi.raw.sec_contexts.init_sec_context` to restrict the set of
    enctypes which will be negotiated during context establisment to those in
    the provided list.

    Warning:
        The cred_handle should not be ``GSS_C_NO_CREDENTIAL``.

    Args:
        cred_hande (Creds): the credential handle
        ktypes (List[int]): list of enctypes allowed

    Returns:
        None

    Raises:
        ~gssapi.exceptions.GSSError
    """
    cdef OM_uint32 maj_stat, min_stat

    # This shouldn't ever happen but it's here to satisfy compiler warnings
    cdef size_t ktypes_count = <size_t>len(ktypes)
    if ktypes_count > UINT32_MAX:
        raise ValueError("ktypes list size too large")

    cdef uint32_t count = <uint32_t>ktypes_count
    cdef int32_t *enc_types = <int32_t *>calloc(count, sizeof(int32_t))
    if not enc_types:
        raise MemoryError()

    try:
        for i, val in enumerate(ktypes):
            enc_types[i] = val

        with nogil:
            maj_stat = gss_krb5_set_allowable_enctypes(&min_stat,
                                                       cred_handle.raw_creds,
                                                       count,
                                                       enc_types)

    finally:
        free(enc_types)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)